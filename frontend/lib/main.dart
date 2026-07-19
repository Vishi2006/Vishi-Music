import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';
import 'config.dart';
import 'package:flutter/services.dart' show rootBundle, ByteData, Uint8List;

late AudioHandler _audioHandler;

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;

  MyAudioHandler() {
    _init();
  }

  void _init() {
    // Pipe player events to audio_service state stream
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 2, 4],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> skipToNext() async => onSkipNext?.call();

  @override
  Future<void> skipToPrevious() async => onSkipPrevious?.call();

  @override
  Future<void> fastForward() async {
    final currentPos = _player.position;
    final totalDuration = _player.duration ?? Duration.zero;
    final newPos = currentPos + const Duration(seconds: 10);
    if (newPos < totalDuration) {
      await _player.seek(newPos);
    } else {
      await _player.seek(totalDuration);
    }
  }

  @override
  Future<void> rewind() async {
    final currentPos = _player.position;
    final newPos = currentPos - const Duration(seconds: 10);
    if (newPos > Duration.zero) {
      await _player.seek(newPos);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> updateMediaItem(MediaItem item) async {
    mediaItem.add(item);
  }

  AudioPlayer get playerInstance => _player;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('dart.vm.product') || !kDebugMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  
  _audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.pulkit.frontend.channel.audio',
      androidNotificationChannelName: 'Vishi Music Playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'mipmap/launcher_icon',
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioProvider()),
      ],
      child: const VishiMusicApp(),
    ),
  );
}

class VishiMusicApp extends StatelessWidget {
  const VishiMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000), // Pitch Black
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFFFFF), // White
          secondary: Color(0xFFB3B3B3), // Muted Grey
          surface: Color(0xFF1E1E1E), // Dark Grey
          background: Color(0xFF000000),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1E1E), // Dark Grey
          elevation: 4,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: Color(0xFFB3B3B3)),
          bodyMedium: TextStyle(color: Color(0xFFB3B3B3)),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// --- MODELS ---
class User {
  final String id;
  final String email;
  final String name;

  User({required this.id, required this.email, required this.name});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? json['_id'] ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
    );
  }
}

class Song {
  final String youtubeId;
  final String title;
  final String artist;
  final String thumbnail;
  final String duration;

  Song({
    required this.youtubeId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.duration,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      youtubeId: json['youtubeId'] ?? '',
      title: json['title'] ?? 'Unknown Title',
      artist: json['artist'] ?? 'Unknown Artist',
      thumbnail: json['thumbnail'] ?? '',
      duration: json['duration'] ?? '0:00',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'youtubeId': youtubeId,
      'title': title,
      'artist': artist,
      'thumbnail': thumbnail,
      'duration': duration,
    };
  }
}

class Playlist {
  final String id;
  final String name;
  final List<Song> songs;

  Playlist({
    required this.id,
    required this.name,
    required this.songs,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    var songsList = json['songs'] as List? ?? [];
    List<Song> parsedSongs = songsList.map((s) => Song.fromJson(s)).toList();
    return Playlist(
      id: json['_id'] ?? '',
      name: json['name'] ?? 'Unnamed Playlist',
      songs: parsedSongs,
    );
  }
}

// --- STATE MANAGEMENT (PROVIDER) ---
class AudioProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = (_audioHandler as MyAudioHandler).playerInstance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late GoogleSignIn _googleSignIn;

  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _isLoading = false;
  String _backendUrl = AppConfig.defaultBackendUrl;

  User? _currentUser;
  String? _accessToken;
  bool _authChecking = true;

  List<Playlist> _playlists = [];
  bool _fetchingPlaylists = false;
  String? _authError;
  String? get authError => _authError;

  AudioProvider() {
    final handler = _audioHandler as MyAudioHandler;
    handler.onSkipNext = () => playNext();
    handler.onSkipPrevious = () => playPrevious();

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        playNext();
      }
      notifyListeners();
    });

    _audioPlayer.positionStream.listen((_) => notifyListeners());
    _audioPlayer.durationStream.listen((_) => notifyListeners());
    _audioPlayer.playingStream.listen((_) => notifyListeners());

    _loadEnvAndAutoLogin();
  }

  Future<void> _loadEnvAndAutoLogin() async {
    _authChecking = true;
    notifyListeners();
    String googleClientId = AppConfig.googleWebClientId;
    String envUrl = _backendUrl;
    try {
      final envString = await rootBundle.loadString('.env');
      final lines = const LineSplitter().convert(envString);
      for (var line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('BACKEND_URL=')) {
          envUrl = trimmed.split('BACKEND_URL=')[1].trim();
        } else if (trimmed.startsWith('GOOGLE_WEB_CLIENT_ID=')) {
          googleClientId = trimmed.split('GOOGLE_WEB_CLIENT_ID=')[1].trim();
        }
      }
    } catch (e) {
      debugPrint('No .env file found or failed to load. Using defaults: $e');
    }

    _backendUrl = envUrl;

    // Force override cached backend URL if developer updated .env configuration
    try {
      final lastEnvUrl = await _storage.read(key: 'env_backend_url');
      if (lastEnvUrl != envUrl) {
        await _storage.write(key: 'env_backend_url', value: envUrl);
        await _storage.write(key: 'backend_url', value: envUrl);
      }
    } catch (_) {}

    _googleSignIn = GoogleSignIn(
      serverClientId: googleClientId,
      scopes: ['email', 'profile'],
    );

    await _autoLogin();
  }

  AudioPlayer get player => _audioPlayer;
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  String get backendUrl => _backendUrl;
  List<Playlist> get playlists => _playlists;
  bool get fetchingPlaylists => _fetchingPlaylists;
  User? get currentUser => _currentUser;
  bool get authChecking => _authChecking;
  bool get isAuthenticated => _currentUser != null;

  Song? get currentSong {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      return _queue[_currentIndex];
    }
    return null;
  }

  void setBackendUrl(String url) {
    _backendUrl = url;
    notifyListeners();
  }

  Future<void> _autoLogin() async {
    _authChecking = true;
    notifyListeners();

    try {
      final savedUrl = await _storage.read(key: 'backend_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _backendUrl = savedUrl;
      }

      final refreshToken = await _storage.read(key: 'refresh_token');
      final cachedUser = await _storage.read(key: 'user_info');

      if (refreshToken != null && cachedUser != null) {
        _currentUser = User.fromJson(jsonDecode(cachedUser));
        final success = await refreshAccessToken(refreshToken);
        if (success) {
          fetchPlaylists();
        } else {
          await logout();
        }
      }
    } catch (e) {
      debugPrint('Auto-login error: $e');
    } finally {
      _authChecking = false;
      notifyListeners();
    }
  }

  Future<bool> loginWithGoogle() async {
    _isLoading = true;
    _authError = null;
    notifyListeners();
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _authError = 'Google Sign-In was cancelled by the user.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('Failed to retrieve Google ID Token.');
      }

      final response = await http.post(
        Uri.parse('$_backendUrl/api/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['accessToken'];
        _currentUser = User.fromJson(data['user']);

        await _storage.write(key: 'refresh_token', value: data['refreshToken']);
        await _storage.write(key: 'user_info', value: jsonEncode(data['user']));
        await _storage.write(key: 'backend_url', value: _backendUrl);

        fetchPlaylists();
        return true;
      } else {
        try {
          final body = jsonDecode(response.body);
          _authError = 'Server: ${body['error'] ?? response.reasonPhrase}';
        } catch (_) {
          _authError = 'Server returned status ${response.statusCode}';
        }
      }
    } catch (e) {
      _authError = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> refreshAccessToken([String? existingRefreshToken]) async {
    try {
      final token = existingRefreshToken ?? await _storage.read(key: 'refresh_token');
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('$_backendUrl/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': token}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['accessToken'];
        return true;
      }
    } catch (e) {
      debugPrint('Refresh token error: $e');
    }
    return false;
  }

  Map<String, String> _getAuthHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_accessToken',
    };
  }

  Future<http.Response> _authenticatedGet(String url) async {
    var response = await http.get(Uri.parse(url), headers: _getAuthHeaders());
    if (response.statusCode == 403) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        response = await http.get(Uri.parse(url), headers: _getAuthHeaders());
      } else {
        await logout();
      }
    }
    return response;
  }

  Future<http.Response> _authenticatedPost(String url, Map<String, dynamic> body) async {
    var response = await http.post(Uri.parse(url), headers: _getAuthHeaders(), body: jsonEncode(body));
    if (response.statusCode == 403) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        response = await http.post(Uri.parse(url), headers: _getAuthHeaders(), body: jsonEncode(body));
      } else {
        await logout();
      }
    }
    return response;
  }

  Future<http.Response> _authenticatedDelete(String url) async {
    var response = await http.delete(Uri.parse(url), headers: _getAuthHeaders());
    if (response.statusCode == 403) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        response = await http.delete(Uri.parse(url), headers: _getAuthHeaders());
      } else {
        await logout();
      }
    }
    return response;
  }

  Future<void> logout() async {
    try {
      await http.post(Uri.parse('$_backendUrl/api/auth/logout'), headers: _getAuthHeaders());
    } catch (_) {}

    await _googleSignIn.signOut();
    _currentUser = null;
    _accessToken = null;
    _queue = [];
    _currentIndex = -1;
    _playlists = [];
    _audioPlayer.stop();

    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'user_info');
    notifyListeners();
  }

  Future<void> playFromQueue(List<Song> newQueue, int index) async {
    _queue = List.from(newQueue);
    _currentIndex = index;
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      await _loadAndPlay(currentSong!);
    }
  }

  Future<void> playSongDirectly(Song song) async {
    final existingIndex = _queue.indexWhere((s) => s.youtubeId == song.youtubeId);
    if (existingIndex != -1) {
      _currentIndex = existingIndex;
    } else {
      _queue.add(song);
      _currentIndex = _queue.length - 1;
    }
    await _loadAndPlay(song);
  }

  void addToQueue(Song song) {
    _queue.add(song);
    notifyListeners();
  }

  Future<ui.Image> _loadUiImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  Future<Uri?> _getArtworkUri(Song song) async {
    if (song.thumbnail.isEmpty) return null;
    try {
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/${song.youtubeId}_composite.png');
      if (await file.exists()) {
        return file.uri;
      }

      // Download thumbnail
      final response = await http.get(Uri.parse(song.thumbnail)).timeout(const Duration(milliseconds: 1000));
      if (response.statusCode != 200) return null;
      final thumbnailBytes = response.bodyBytes;

      // Load logo from assets
      final ByteData logoData = await rootBundle.load('assets/logo.png');
      final logoBytes = logoData.buffer.asUint8List();

      // Decode both
      final ui.Image thumbImage = await _loadUiImage(thumbnailBytes);
      final ui.Image logoImage = await _loadUiImage(logoBytes);

      // Draw onto canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 400));

      paintImage(
        canvas: canvas,
        rect: const Rect.fromLTWH(0, 0, 400, 400),
        image: thumbImage,
        fit: BoxFit.cover,
      );

      // Draw app logo overlay in the bottom-right corner (100x100 size)
      paintImage(
        canvas: canvas,
        rect: const Rect.fromLTWH(285, 285, 100, 100),
        image: logoImage,
        fit: BoxFit.contain,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(400, 400);
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes != null) {
        await file.writeAsBytes(pngBytes.buffer.asUint8List());
        return file.uri;
      }
    } catch (e) {
      debugPrint('Error creating composite artwork: $e');
    }
    return null;
  }

  void _preCacheArtwork(Song song) {
    if (song.thumbnail.isEmpty) return;
    try {
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/${song.youtubeId}_composite.png');
      file.exists().then((exists) async {
        if (!exists) {
          // Download and generate composite artwork in the background
          await _getArtworkUri(song);
        }
      });
    } catch (_) {}
  }

  Future<void> _loadAndPlay(Song song) async {
    _isLoading = true;
    notifyListeners();
    try {
      final streamUrl = '$_backendUrl/api/stream?id=${song.youtubeId}';
      final artUri = await _getArtworkUri(song);

      // Pre-cache next song's artwork in the background
      if (_currentIndex < _queue.length - 1) {
        _preCacheArtwork(_queue[_currentIndex + 1]);
      }

      // Tell audio_service the metadata of the current song
      (_audioHandler as MyAudioHandler).updateMediaItem(
        MediaItem(
          id: song.youtubeId,
          album: "Vishi Music",
          title: song.title,
          artist: song.artist,
          artUri: artUri,
        ),
      );

      // Tell player to target playing state before/during load
      _audioPlayer.play();

      await _audioPlayer.setAudioSource(
        LockCachingAudioSource(
          Uri.parse(streamUrl),
        ),
      );
      
      // Ensure play is triggered
      _audioPlayer.play();
    } catch (e) {
      debugPrint('Playback error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void togglePlay() {
    if (_audioPlayer.playing) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
    notifyListeners();
  }

  void seekForward() {
    final currentPos = _audioPlayer.position;
    final totalDuration = _audioPlayer.duration ?? Duration.zero;
    final newPos = currentPos + const Duration(seconds: 10);
    if (newPos < totalDuration) {
      _audioPlayer.seek(newPos);
    } else {
      _audioPlayer.seek(totalDuration);
    }
  }

  void seekBackward() {
    final currentPos = _audioPlayer.position;
    final newPos = currentPos - const Duration(seconds: 10);
    if (newPos > Duration.zero) {
      _audioPlayer.seek(newPos);
    } else {
      _audioPlayer.seek(Duration.zero);
    }
  }

  void playNext() {
    if (_queue.isEmpty) return;
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      notifyListeners();
      _loadAndPlay(currentSong!);
    }
  }

  void playPrevious() {
    if (_queue.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
      notifyListeners();
      _loadAndPlay(currentSong!);
    }
  }

  Future<List<Song>> searchSongs(String query) async {
    try {
      final res = await _authenticatedGet('$_backendUrl/api/search?q=${Uri.encodeComponent(query)}');
      debugPrint('Search response status: ${res.statusCode} | body: ${res.body}');
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        return data.map((json) => Song.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Search API error: $e');
    }
    return [];
  }

  Future<void> fetchPlaylists() async {
    _fetchingPlaylists = true;
    notifyListeners();
    try {
      final res = await _authenticatedGet('$_backendUrl/api/playlists');
      debugPrint('Fetch playlists response status: ${res.statusCode} | body: ${res.body}');
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        _playlists = data.map((json) => Playlist.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching playlists: $e');
    } finally {
      _fetchingPlaylists = false;
      notifyListeners();
    }
  }

  Future<bool> createPlaylist(String name) async {
    try {
      final res = await _authenticatedPost('$_backendUrl/api/playlists', {'name': name});
      debugPrint('Create playlist response status: ${res.statusCode} | body: ${res.body}');
      if (res.statusCode == 201) {
        await fetchPlaylists();
        return true;
      }
    } catch (e) {
      debugPrint('Error creating playlist: $e');
    }
    return false;
  }

  Future<bool> deletePlaylist(String playlistId) async {
    try {
      final res = await _authenticatedDelete('$_backendUrl/api/playlists/$playlistId');
      debugPrint('Delete playlist response status: ${res.statusCode} | body: ${res.body}');
      if (res.statusCode == 200) {
        await fetchPlaylists();
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting playlist: $e');
    }
    return false;
  }

  Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    try {
      final res = await _authenticatedPost('$_backendUrl/api/playlists/add', {
        'playlistId': playlistId,
        'song': song.toJson(),
      });
      debugPrint('Add song response status: ${res.statusCode} | body: ${res.body}');
      if (res.statusCode == 200) {
        await fetchPlaylists();
        return true;
      }
    } catch (e) {
      debugPrint('Error adding song to playlist: $e');
    }
    return false;
  }

  Future<bool> removeSongFromPlaylist(String playlistId, String youtubeId) async {
    try {
      final res = await _authenticatedPost('$_backendUrl/api/playlists/remove', {
        'playlistId': playlistId,
        'songId': youtubeId,
      });
      debugPrint('Remove song response status: ${res.statusCode} | body: ${res.body}');
      if (res.statusCode == 200) {
        await fetchPlaylists();
        return true;
      }
    } catch (e) {
      debugPrint('Error removing song from playlist: $e');
    }
    return false;
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

// --- AUTH WRAPPER (GATEKEEPER) ---
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AudioProvider>(context);

    if (provider.authChecking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return provider.isAuthenticated ? const MainContainer() : const LoginScreen();
  }
}

// --- LOGIN SCREEN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<AudioProvider>(context, listen: false);
    _urlController.text = provider.backendUrl;
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AudioProvider>(context);

    return Scaffold(
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF1E1E1E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/logo.png',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.music_note_outlined, size: 64, color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'VISHI MUSIC',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your Zero-Storage Music Streaming App',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 64),
            if (provider.isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: () async {
                  final success = await provider.loginWithGoogle();
                   if (!success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(provider.authError ?? 'Failed to sign in. Please try again.'),
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                },
                icon: Image.network(
                  'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1024px-Google_%22G%22_logo.svg.png',
                  height: 24,
                  width: 24,
                  errorBuilder: (_, __, ___) => const Icon(Icons.account_circle),
                ),
                label: const Text(
                  'Sign in with Google',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- CONTAINER FOR APP (NAVIGATION) ---
class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const HomeScreen(),
    const SearchScreen(),
    const PlaylistsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final currentSong = audioProvider.currentSong;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _tabs[_currentIndex]),
            if (currentSong != null) const MiniPlayer(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white38,
        backgroundColor: const Color(0xFF121212), // Dark Charcoal
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_play_outlined),
            activeIcon: Icon(Icons.playlist_play),
            label: 'Playlists',
          ),
        ],
      ),
    );
  }
}

// --- HOME SCREEN ---
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AudioProvider>(context);
    final user = provider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => provider.logout(),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1E1E1E),
                      Color(0xFF333333),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, ${user?.name ?? "User"}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Stream high quality music straight from YouTube without ads or track limits.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Account: ${user?.email}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Playing Queue',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (provider.queue.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text(
                      'No songs in queue. Use Search tab to find and play music!',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: provider.queue.length,
                  itemBuilder: (context, index) {
                    final song = provider.queue[index];
                    final isCurrent = index == provider.currentIndex;
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: song.thumbnail.isNotEmpty
                            ? Image.network(
                                song.thumbnail,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
                              )
                            : const Icon(Icons.music_note),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.white,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(song.artist, maxLines: 1),
                      trailing: Text(song.duration),
                      onTap: () => provider.playFromQueue(provider.queue, index),
                    );
                  },
                )
            ],
          ),
        ),
      ),
    );
  }
}

// --- SEARCH SCREEN ---
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<Song> _searchResults = [];
  bool _searching = false;

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _searchResults = [];
    });

    final provider = Provider.of<AudioProvider>(context, listen: false);
    try {
      final results = await provider.searchSongs(query);
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching: $e')),
      );
    } finally {
      setState(() {
        _searching = false;
      });
    }
  }

  void _showAddToPlaylistDialog(Song song) {
    final provider = Provider.of<AudioProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add to Playlist'),
          content: SizedBox(
            width: double.maxFinite,
            child: provider.playlists.isEmpty
                ? const Text('No playlists found. Create one first!')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: provider.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = provider.playlists[index];
                      return ListTile(
                        title: Text(playlist.name),
                        trailing: const Icon(Icons.add),
                        onTap: () async {
                          final success = await provider.addSongToPlaylist(playlist.id, song);
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Added to ${playlist.name}')),
                            );
                          }
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AudioProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Youtube'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists, etc...',
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _performSearch,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? const Center(child: Text('Search for songs above'))
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final song = _searchResults[index];
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: song.thumbnail.isNotEmpty
                                  ? Image.network(
                                      song.thumbnail,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
                                    )
                                  : const Icon(Icons.music_note),
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(song.artist, maxLines: 1),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.playlist_add),
                                  onPressed: () => _showAddToPlaylistDialog(song),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () {
                                    provider.addToQueue(song);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Added to Queue')),
                                    );
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              provider.playSongDirectly(song);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// --- PLAYLISTS SCREEN ---
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final _playlistNameController = TextEditingController();

  void _showCreatePlaylistDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Playlist'),
          content: TextField(
            controller: _playlistNameController,
            decoration: const InputDecoration(hintText: 'My Playlist Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = _playlistNameController.text.trim();
                if (name.isNotEmpty) {
                  final provider = Provider.of<AudioProvider>(context, listen: false);
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  final success = await provider.createPlaylist(name);
                  if (success) {
                    _playlistNameController.clear();
                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(content: Text('Playlist "$name" created!')),
                    );
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Failed to create playlist. Make sure the name is unique.')),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AudioProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Playlists'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreatePlaylistDialog,
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.fetchPlaylists(),
        child: provider.fetchingPlaylists
            ? const Center(child: CircularProgressIndicator())
            : provider.playlists.isEmpty
                ? const Center(child: Text('No playlists. Tap the + icon to make one.'))
                : ListView.builder(
                    itemCount: provider.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = provider.playlists[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF1E1E1E),
                          child: Icon(Icons.playlist_play, color: Colors.white),
                        ),
                        title: Text(playlist.name),
                        subtitle: Text('${playlist.songs.length} song(s)'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white60),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Playlist'),
                                content: Text('Are you sure you want to delete "${playlist.name}"?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final messenger = ScaffoldMessenger.of(context);
                              final success = await provider.deletePlaylist(playlist.id);
                              if (success) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Playlist "${playlist.name}" deleted.')),
                                );
                              } else {
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Failed to delete playlist.')),
                                );
                              }
                            }
                          },
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlaylistDetailScreen(playlist: playlist),
                            ),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

// --- PLAYLIST DETAIL SCREEN ---
class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AudioProvider>(context);
    final currentPlaylist = provider.playlists.firstWhere(
      (p) => p.id == playlist.id,
      orElse: () => playlist,
    );

    final showMiniPlayer = provider.currentSong != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPlaylist.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: currentPlaylist.songs.isEmpty
                ? const Center(child: Text('This playlist is empty. Add songs via search tab.'))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            provider.playFromQueue(currentPlaylist.songs, 0);
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('PLAY ALL PLAYLIST'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: currentPlaylist.songs.length,
                          itemBuilder: (context, index) {
                            final song = currentPlaylist.songs[index];
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: song.thumbnail.isNotEmpty
                                    ? Image.network(
                                        song.thumbnail,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
                                      )
                                    : const Icon(Icons.music_note),
                              ),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(song.artist, maxLines: 1),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(song.duration),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.white60),
                                    onPressed: () async {
                                      final messenger = ScaffoldMessenger.of(context);
                                      final success = await provider.removeSongFromPlaylist(currentPlaylist.id, song.youtubeId);
                                      if (success) {
                                        messenger.showSnackBar(
                                          SnackBar(content: Text('Removed "${song.title}" from playlist.')),
                                        );
                                      } else {
                                        messenger.showSnackBar(
                                          const SnackBar(content: Text('Failed to remove song.')),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                provider.playFromQueue(currentPlaylist.songs, index);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          if (showMiniPlayer) const MiniPlayer(),
        ],
      ),
    );
  }
}

// --- MINI PLAYER BAR ---
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AudioProvider>(context);
    final song = provider.currentSong;

    if (song == null) return const SizedBox.shrink();

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0xFF000000),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (context) => const FullPlayerScreen(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFF1E1E1E),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: song.thumbnail.isNotEmpty
                  ? Image.network(
                      song.thumbnail,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
                    )
                  : const Icon(Icons.music_note),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (provider.isLoading)
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              IconButton(
                icon: Icon(
                  provider.player.playing ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: provider.togglePlay,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: provider.playNext,
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// --- FULL SCREEN EXPANDED PLAYER ---
class FullPlayerScreen extends StatelessWidget {
  const FullPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AudioProvider>(context);
    final song = provider.currentSong;

    if (song == null) return const SizedBox.shrink();

    final position = provider.player.position;
    final duration = provider.player.duration ?? Duration.zero;

    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 32),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: song.thumbnail.isNotEmpty
                ? Image.network(
                    song.thumbnail,
                    width: 250,
                    height: 250,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 250,
                      height: 250,
                      color: const Color(0xFF1E1E1E),
                      child: const Icon(Icons.music_note, size: 80),
                    ),
                  )
                : Container(
                    width: 250,
                    height: 250,
                    color: const Color(0xFF1E1E1E),
                    child: const Icon(Icons.music_note, size: 80),
                  ),
          ),
          const SizedBox(height: 24),
          Text(
            song.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            song.artist,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Slider(
            activeColor: Theme.of(context).colorScheme.primary,
            inactiveColor: Colors.grey[800],
            min: 0.0,
            max: duration.inMilliseconds.toDouble(),
            value: position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble()),
            onChanged: (val) {
              provider.player.seek(Duration(milliseconds: val.toInt()));
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position)),
                Text(_formatDuration(duration)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.skip_previous),
                onPressed: provider.playPrevious,
              ),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.replay_10),
                onPressed: provider.seekBackward,
              ),
              if (provider.isLoading)
                const SizedBox(
                  width: 64,
                  height: 64,
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                IconButton(
                  iconSize: 64,
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icon(
                    provider.player.playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  ),
                  onPressed: provider.togglePlay,
                ),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.forward_10),
                onPressed: provider.seekForward,
              ),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.skip_next),
                onPressed: provider.playNext,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

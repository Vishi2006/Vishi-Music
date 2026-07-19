const Playlist = require('../models/Playlist');
const logger = require('../utils/logger');

exports.getPlaylists = async (req, res) => {
  try {
    const playlists = await Playlist.find({ userId: req.user.id });
    res.json(playlists);
  } catch (error) {
    logger.error('Fetch playlists error:', error);
    res.status(500).json({ error: 'Failed to fetch playlists' });
  }
};

exports.createPlaylist = async (req, res) => {
  try {
    const { name } = req.body;
    if (!name || typeof name !== 'string' || name.trim() === '') {
      return res.status(400).json({ error: 'Playlist name is required' });
    }

    const playlistName = name.trim();

    const existing = await Playlist.findOne({ name: playlistName, userId: req.user.id });
    if (existing) {
      return res.status(400).json({ error: 'Playlist already exists for this user' });
    }

    const playlist = new Playlist({ name: playlistName, userId: req.user.id, songs: [] });
    await playlist.save();
    res.status(201).json(playlist);
  } catch (error) {
    logger.error('Create playlist error:', error);
    res.status(500).json({ error: 'Failed to create playlist' });
  }
};

exports.addSongToPlaylist = async (req, res) => {
  try {
    const { playlistId, song } = req.body;
    if (!playlistId || !song) {
      return res.status(400).json({ error: 'playlistId and song metadata are required' });
    }

    const { youtubeId, title, artist, thumbnail, duration } = song;
    if (!youtubeId || !title || !artist || !thumbnail || !duration) {
      return res.status(400).json({ error: 'Song metadata is incomplete' });
    }

    const playlist = await Playlist.findOne({ _id: playlistId, userId: req.user.id });
    if (!playlist) {
      return res.status(404).json({ error: 'Playlist not found or access denied' });
    }

    const duplicate = playlist.songs.some(s => s.youtubeId === youtubeId);
    if (duplicate) {
      return res.status(400).json({ error: 'Song already exists in this playlist' });
    }

    playlist.songs.push({ youtubeId, title, artist, thumbnail, duration });
    await playlist.save();

    res.json(playlist);
  } catch (error) {
    logger.error('Add to playlist error:', error);
    res.status(500).json({ error: 'Failed to add song to playlist' });
  }
};

exports.deletePlaylist = async (req, res) => {
  try {
    const { id } = req.params;
    const playlist = await Playlist.findOneAndDelete({ _id: id, userId: req.user.id });
    if (!playlist) {
      return res.status(404).json({ error: 'Playlist not found or access denied' });
    }
    res.json({ message: 'Playlist deleted successfully' });
  } catch (error) {
    logger.error('Delete playlist error:', error);
    res.status(500).json({ error: 'Failed to delete playlist' });
  }
};

exports.removeSongFromPlaylist = async (req, res) => {
  try {
    const { playlistId, songId } = req.body;
    if (!playlistId || !songId) {
      return res.status(400).json({ error: 'playlistId and songId are required' });
    }

    const playlist = await Playlist.findOne({ _id: playlistId, userId: req.user.id });
    if (!playlist) {
      return res.status(404).json({ error: 'Playlist not found or access denied' });
    }

    playlist.songs = playlist.songs.filter(s => s.youtubeId !== songId);
    await playlist.save();

    res.json(playlist);
  } catch (error) {
    logger.error('Remove from playlist error:', error);
    res.status(500).json({ error: 'Failed to remove song from playlist' });
  }
};

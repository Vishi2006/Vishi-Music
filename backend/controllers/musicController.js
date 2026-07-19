const ytSearch = require('yt-search');
const youtubedl = require('youtube-dl-exec');
const https = require('https');
const logger = require('../utils/logger');

// Auto-convert cookies.json to cookies.txt if cookies.json exists
try {
  const path = require('path');
  const fs = require('fs');
  const jsonPath = path.join(__dirname, '..', 'cookies.json');
  const txtPath = path.join(__dirname, '..', 'cookies.txt');

  if (fs.existsSync(jsonPath)) {
    const jsonStr = fs.readFileSync(jsonPath, 'utf8');
    const cookies = JSON.parse(jsonStr);
    
    let netscapeText = '# Netscape HTTP Cookie File\n# This file was auto-generated from cookies.json\n\n';
    for (const cookie of cookies) {
      const domain = cookie.domain || '';
      const flag = domain.startsWith('.') ? 'TRUE' : 'FALSE';
      const pathVal = cookie.path || '/';
      const secure = cookie.secure ? 'TRUE' : 'FALSE';
      const expires = cookie.expirationDate ? Math.round(cookie.expirationDate) : 0;
      const name = cookie.name || '';
      const value = cookie.value || '';
      
      netscapeText += `${domain}\t${flag}\t${pathVal}\t${secure}\t${expires}\t${name}\t${value}\n`;
    }
    
    fs.writeFileSync(txtPath, netscapeText, 'utf8');
    logger.log('Successfully generated cookies.txt from cookies.json');
  }
} catch (err) {
  logger.error('Error converting cookies.json to Netscape format:', err);
}

// User-Agent Rotation Helper
const userAgents = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2.1 Safari/605.1.15',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
];

function getRandomUserAgent() {
  return userAgents[Math.floor(Math.random() * userAgents.length)];
}

function formatDuration(seconds) {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
}

exports.searchSongs = async (req, res) => {
  try {
    const query = req.query.q;
    if (!query || typeof query !== 'string' || query.trim() === '') {
      return res.status(400).json({ error: 'Search query parameter "q" is required' });
    }

    const sanitizedQuery = query.replace(/[^\w\s-]/g, '').trim();
    const results = await ytSearch(sanitizedQuery);
    const videos = results.videos.slice(0, 15);

    const formattedSongs = videos.map(video => ({
      youtubeId: video.videoId,
      title: video.title,
      artist: video.author.name || 'Unknown Artist',
      thumbnail: video.thumbnail || video.image,
      duration: video.duration.timestamp || formatDuration(video.seconds)
    }));

    res.json(formattedSongs);
  } catch (error) {
    logger.error('Search error:', error);
    res.status(500).json({ error: 'Failed to search songs' });
  }
};

// Simple in-memory cache for resolved stream info
// Key: videoId, Value: { bestAudio: Object, expiresAt: number }
const streamCache = new Map();
const CACHE_TTL = 30 * 60 * 1000; // 30 minutes cache

exports.streamSong = async (req, res) => {
  try {
    const id = req.query.id;
    if (!id || typeof id !== 'string' || !/^[a-zA-Z0-9_-]{11}$/.test(id)) {
      return res.status(400).json({ error: 'Invalid or missing YouTube Video ID' });
    }

    let bestAudio = null;
    const cached = streamCache.get(id);
    const now = Date.now();

    if (cached && cached.expiresAt > now) {
      bestAudio = cached.bestAudio;
      logger.log(`Stream cache hit for video: ${id}`);
    } else {
      logger.log(`Stream cache miss for video: ${id}. Resolving formats via yt-dlp...`);
      const videoUrl = `https://www.youtube.com/watch?v=${id}`;
      
      // Check if a cookies.txt file exists in the backend directory
      const path = require('path');
      const fs = require('fs');
      
      const options = {
        dumpSingleJson: true,
        noCheckCertificates: true,
        noWarnings: true,
        preferFreeFormats: true,
      };

      const cookiesPath = path.join(__dirname, '..', 'cookies.txt');
      if (fs.existsSync(cookiesPath)) {
        options.cookies = cookiesPath;
      }

      // Fetch video formats from youtube-dl-exec
      const output = await youtubedl(videoUrl, options);

      let audioFormats = output.formats.filter(f => f.acodec !== 'none' && f.vcodec === 'none' && f.ext === 'm4a');
      if (audioFormats.length === 0) {
        audioFormats = output.formats.filter(f => f.acodec !== 'none' && f.vcodec === 'none');
      }

      if (audioFormats.length === 0) {
        return res.status(404).json({ error: 'No audio formats found for this video' });
      }

      bestAudio = audioFormats[audioFormats.length - 1];

      // Cache the result
      streamCache.set(id, {
        bestAudio,
        expiresAt: now + CACHE_TTL
      });
    }

    // Forward the Range header if sent by the client
    const headers = {
      'User-Agent': getRandomUserAgent()
    };
    if (req.headers.range) {
      headers['Range'] = req.headers.range;
    }

    const streamReq = https.get(bestAudio.url, { headers }, (streamRes) => {
      // Set Express status code matching YouTube response (e.g., 206 Partial Content)
      res.statusCode = streamRes.statusCode;
      
      // Copy key stream headers
      const headersToCopy = [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges'
      ];
      headersToCopy.forEach(header => {
        if (streamRes.headers[header]) {
          res.setHeader(header, streamRes.headers[header]);
        }
      });

      // Default headers in case they are missing
      if (!res.getHeader('content-type')) {
        res.setHeader('Content-Type', bestAudio.mimeType || 'audio/webm');
      }
      if (!res.getHeader('accept-ranges')) {
        res.setHeader('Accept-Ranges', 'bytes');
      }

      streamRes.pipe(res);
    });

    streamReq.on('error', (err) => {
      logger.error('Streaming connection error:', err);
      if (!res.headersSent) {
        res.status(500).send('Streaming failed');
      }
    });

    req.on('close', () => {
      streamReq.destroy();
    });

  } catch (error) {
    logger.error('Stream setup error:', error);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to stream audio' });
    }
  }
};

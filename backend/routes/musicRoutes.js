const express = require('express');
const router = express.Router();
const musicController = require('../controllers/musicController');
const authenticateToken = require('../middlewares/authMiddleware');
const streamRateLimiter = require('../middlewares/rateLimiter');

router.get('/search', authenticateToken, musicController.searchSongs);
router.get('/stream', streamRateLimiter, musicController.streamSong);

module.exports = router;

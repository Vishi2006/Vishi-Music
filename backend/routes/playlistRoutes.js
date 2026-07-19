const express = require('express');
const router = express.Router();
const playlistController = require('../controllers/playlistController');
const authenticateToken = require('../middlewares/authMiddleware');

router.get('/', authenticateToken, playlistController.getPlaylists);
router.post('/', authenticateToken, playlistController.createPlaylist);
router.post('/add', authenticateToken, playlistController.addSongToPlaylist);
router.post('/remove', authenticateToken, playlistController.removeSongFromPlaylist);
router.delete('/:id', authenticateToken, playlistController.deletePlaylist);

module.exports = router;

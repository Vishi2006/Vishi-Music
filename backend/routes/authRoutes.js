const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');
const authenticateToken = require('../middlewares/authMiddleware');

router.post('/google', authController.googleLogin);
router.post('/refresh', authController.refreshToken);
router.post('/logout', authenticateToken, authController.logout);

module.exports = router;

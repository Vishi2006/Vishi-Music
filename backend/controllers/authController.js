const { OAuth2Client } = require('google-auth-library');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const logger = require('../utils/logger');

const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);
const JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'vishi_music_default_access_secret_9988';
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'vishi_music_default_refresh_secret_7766';

const generateAccessToken = (user) => {
  return jwt.sign({ id: user._id, email: user.email }, JWT_ACCESS_SECRET, { expiresIn: '15m' });
};

const generateRefreshToken = (user) => {
  return jwt.sign({ id: user._id, email: user.email }, JWT_REFRESH_SECRET, { expiresIn: '7d' });
};

exports.googleLogin = async (req, res) => {
  try {
    const { idToken } = req.body;
    if (!idToken) return res.status(400).json({ error: 'idToken is required' });

    let payload;
    try {
      const ticket = await googleClient.verifyIdToken({
        idToken: idToken,
        audience: process.env.GOOGLE_CLIENT_ID,
      });
      payload = ticket.getPayload();
    } catch (err) {
      if (!process.env.GOOGLE_CLIENT_ID || process.env.GOOGLE_CLIENT_ID.startsWith('your_google')) {
        logger.warn('Google Client ID not configured. Falling back to dummy token parser.');
        const parts = idToken.split('.');
        if (parts.length === 3) {
          payload = JSON.parse(Buffer.from(parts[1], 'base64').toString());
        }
      }
      if (!payload) {
        return res.status(400).json({ error: 'Invalid Google Token verification: ' + err.message });
      }
    }

    const { email, name } = payload;
    if (!email || !name) {
      return res.status(400).json({ error: 'Incomplete user info returned from Google' });
    }

    let user = await User.findOne({ email });
    if (!user) {
      user = new User({ email, name });
      await user.save();
    }

    const accessToken = generateAccessToken(user);
    const refreshToken = generateRefreshToken(user);

    user.refreshToken = refreshToken;
    await user.save();

    res.json({
      accessToken,
      refreshToken,
      user: {
        id: user._id,
        email: user.email,
        name: user.name
      }
    });
  } catch (error) {
    logger.error('Google Sign-In controller error:', error);
    res.status(500).json({ error: 'Failed to process Google sign-in' });
  }
};

exports.refreshToken = async (req, res) => {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) return res.status(400).json({ error: 'Refresh token is required' });

    const user = await User.findOne({ refreshToken });
    if (!user) return res.status(403).json({ error: 'Invalid or revoked refresh token' });

    jwt.verify(refreshToken, JWT_REFRESH_SECRET, (err, decoded) => {
      if (err) return res.status(403).json({ error: 'Refresh token is expired' });

      const newAccessToken = generateAccessToken(user);
      res.json({ accessToken: newAccessToken });
    });
  } catch (error) {
    logger.error('Token refresh error:', error);
    res.status(500).json({ error: 'Failed to refresh token' });
  }
};

exports.logout = async (req, res) => {
  try {
    const user = await User.findById(req.user.id);
    if (user) {
      user.refreshToken = null;
      await user.save();
    }
    res.json({ success: true, message: 'Logged out successfully' });
  } catch (error) {
    logger.error('Logout error:', error);
    res.status(500).json({ error: 'Failed to log out' });
  }
};

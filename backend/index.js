const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const dotenv = require('dotenv');

// Load environment variables immediately
dotenv.config();

const connectDB = require('./config/db');
const logger = require('./utils/logger');

// Import routes
const authRoutes = require('./routes/authRoutes');
const musicRoutes = require('./routes/musicRoutes');
const playlistRoutes = require('./routes/playlistRoutes');

// Connect to MongoDB
connectDB();

const app = express();
const PORT = process.env.PORT;

// Security & global Middlewares
app.use(helmet());
app.use(cors());
app.use(express.json());

// Request Logger (Development & Debug)
app.use((req, res, next) => {
  console.log(`--> ${req.method} ${req.originalUrl}`);
  res.on('finish', () => {
    console.log(`<-- ${req.method} ${req.originalUrl} | Status: ${res.statusCode}`);
  });
  next();
});

// Routes Mounts
app.use('/api/auth', authRoutes);
app.use('/api', musicRoutes); // search, stream
app.use('/api/playlists', playlistRoutes);
app.get('/', (req, res) => {
  res.send("Vishi Music Backend is running!");
});

// Process Protection
process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception occurred:', err);
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

// Server Init
app.listen(PORT, () => {
  console.log(`Vishi Music Backend running on port ${PORT}`);
});

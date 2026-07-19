const mongoose = require('mongoose');

const SongSchema = new mongoose.Schema({
  youtubeId: { type: String, required: true },
  title: { type: String, required: true },
  artist: { type: String, required: true },
  thumbnail: { type: String, required: true },
  duration: { type: String, required: true }
});

const PlaylistSchema = new mongoose.Schema({
  name: { type: String, required: true },
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  songs: [SongSchema]
}, { timestamps: true });

// A user cannot have multiple playlists with the same name
PlaylistSchema.index({ name: 1, userId: 1 }, { unique: true });

module.exports = mongoose.model('Playlist', PlaylistSchema);

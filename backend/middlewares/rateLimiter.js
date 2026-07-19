const streamCooldowns = new Map();
const STREAM_COOLDOWN_MS = 7000;

const streamRateLimiter = (req, res, next) => {
  const ip = req.ip || req.headers['x-forwarded-for'] || req.socket.remoteAddress;
  const now = Date.now();

  if (streamCooldowns.has(ip)) {
    const lastRequestTime = streamCooldowns.get(ip);
    const timeElapsed = now - lastRequestTime;

    if (timeElapsed < STREAM_COOLDOWN_MS) {
      const waitTime = Math.ceil((STREAM_COOLDOWN_MS - timeElapsed) / 1000);
      return res.status(429).json({
        error: `Too Many Requests. Please wait ${waitTime} second(s) before request.`
      });
    }
  }

  streamCooldowns.set(ip, now);
  next();
};

module.exports = streamRateLimiter;

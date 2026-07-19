const logger = {
  log: (...args) => {
    if (process.env.NODE_ENV !== 'production') {
      console.log(...args);
    }
  },
  warn: (...args) => {
    if (process.env.NODE_ENV !== 'production') {
      console.warn(...args);
    }
  },
  error: (...args) => {
    // We keep error logs in production to trace crashes, but only log essentials
    console.error(...args);
  }
};

module.exports = logger;

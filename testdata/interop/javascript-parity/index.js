function decorate(fn) {
  return fn;
}

class BaseLogger {
  write(message) {
    return message.trim();
  }
}

class FileLogger extends BaseLogger {
  log(message) {
    return this.write(message);
  }
}

const settings = { mode: "json" };

const boot = decorate(function boot() {
  const logger = new FileLogger();
  settings.mode = "text";
  return logger.log(" ready ");
});

boot();

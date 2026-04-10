class BaseLogger {
  format(message) {
    return message;
  }
}

class TraceLogger extends BaseLogger {
  format(message) {
    return `[trace] ${super.format(message)}`;
  }
}

function emit(message) {
  const logger = new TraceLogger();
  return logger.format(message);
}

export function run(message) {
  return emit(message);
}

run("interop");

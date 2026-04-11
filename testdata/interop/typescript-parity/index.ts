interface Runner {
  run(): string;
}

interface Configured {
  mode: string;
}

function annotate<T>(value: T): T {
  return value;
}

class Worker implements Runner, Configured {
  mode = "batch";

  run(): string {
    return this.mode;
  }
}

export function boot(): string {
  const worker = annotate(new Worker());
  return worker.run();
}

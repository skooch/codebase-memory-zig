export interface Worker {
  execute(input: number): number;
}

class WorkerImpl implements Worker {
  execute(input: number): number {
    return input + 1;
  }
}

export const makeWorker = (seed: number): Worker => ({
  execute: (input: number) => input * seed,
});

export function run(): number {
  const worker: Worker = new WorkerImpl();
  const factory: Worker = makeWorker(2);
  return worker.execute(3) + factory.execute(4);
}

run();

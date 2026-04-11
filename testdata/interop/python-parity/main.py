from models import Worker as ActiveWorker
from models import trace


@trace
def bootstrap() -> ActiveWorker:
    worker = ActiveWorker("primary")
    worker.configure("mode", "batch")
    worker.run()
    return worker

from models import Worker as ActiveWorker
from models import trace

default_mode = "batch"


def get_max_connections() -> int:
    return 10


@trace
def bootstrap() -> ActiveWorker:
    worker = ActiveWorker("primary")
    worker.configure("mode", "batch")
    worker.run()
    return worker

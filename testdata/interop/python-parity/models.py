class BaseWorker:
    def __init__(self, name: str) -> None:
        self.name = name
        self.settings: dict[str, str] = {}

    def configure(self, key: str, value: str) -> None:
        self.settings[key] = value


def trace(fn):
    return fn


class Worker(BaseWorker):
    def run(self) -> str:
        return self.name.upper()

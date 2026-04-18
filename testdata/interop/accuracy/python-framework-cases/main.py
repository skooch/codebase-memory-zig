from flask import Flask

app = Flask(__name__)


def build_router():
    return {"GET /shadow": "not_a_route"}


@app.get("/health")
def health_check():
    return read_status()


def read_status():
    return "ok"


def create_app():
    router = build_router()
    return {"app": app, "router": router}


def not_a_route():
    return "helper"

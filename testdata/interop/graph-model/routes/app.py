from flask import Flask

app = Flask(__name__)


@app.route("/api/users")
def list_users():
    return []


def send(path):
    return path


def fetch_users():
    return send("/api/users")

from flask import Flask
import requests

app = Flask(__name__)


@app.get("/api/users")
def list_users():
    return []


def fetch_users():
    return requests.get("/api/users")

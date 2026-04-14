import requests


def fetch_users():
    response = requests.get("http://api.example.com/users")
    return response.json()


def create_user(name, email):
    response = requests.post("http://api.example.com/users", json={"name": name, "email": email})
    return response.json()


def health_check():
    return requests.head("http://api.example.com/health")

from fastapi import FastAPI
import requests

app = FastAPI()


def list_orders():
    return []


app.add_api_route("/api/orders", endpoint=list_orders, methods=["GET"])


def fetch_orders():
    return requests.request("GET", "/api/orders")

import axios from "axios";

type Handler = () => unknown;

const app = {
  get(path: string, handler: Handler) {
    return { path, handler };
  },
};

function listOrders() {
  return [];
}

app.get("/api/orders", listOrders);

export async function fetchOrders() {
  return axios.get("/api/orders");
}

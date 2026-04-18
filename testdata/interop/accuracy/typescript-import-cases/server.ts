export function parsePayload(raw: string) {
  return raw.trim().toUpperCase();
}

export function handleRequest(payload: string) {
  return payload.length;
}

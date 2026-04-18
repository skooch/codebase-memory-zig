import { handleRequest as runHandler, parsePayload } from "./server";
import * as telemetry from "./telemetry";

export function run(raw: string) {
  telemetry.markStart();
  const payload = parsePayload(raw);
  return runHandler(payload);
}

export function localOnly(value: string) {
  return value.trim();
}

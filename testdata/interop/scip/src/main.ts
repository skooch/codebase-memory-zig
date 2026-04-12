export function renderMessage(name: string): string {
  const message = `hello ${name}`;
  return message.toUpperCase();
}

export function run(): string {
  return renderMessage("world");
}

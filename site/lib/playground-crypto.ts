import type { EncryptedPacket } from "./playground-rooms";

export function base64url(bytes: Uint8Array): string {
  let text = "";
  for (let i = 0; i < bytes.length; i += 8192) text += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(text).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function unbase64url(text: string, maximumBytes = 300_000): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(text) || text.length > maximumBytes * 4 / 3 + 4) throw new Error("Invalid or oversized encrypted data.");
  const binary = atob(text.replaceAll("-", "+").replaceAll("_", "/"));
  if (binary.length > maximumBytes) throw new Error("Encrypted data exceeds this Playground's limit.");
  return Uint8Array.from(binary, character => character.charCodeAt(0));
}

const additionalData = new TextEncoder().encode("crabrix-playground-v1");
export const newEncryptionSecret = () => base64url(crypto.getRandomValues(new Uint8Array(32)));

async function key(secret: string) {
  const bytes = unbase64url(secret, 32);
  if (bytes.length !== 32) throw new Error("This Playground link has an invalid encryption key.");
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function encryptPlayground(secret: string, bytes: Uint8Array): Promise<EncryptedPacket> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData }, await key(secret), new Uint8Array(bytes));
  return { iv: base64url(iv), data: base64url(new Uint8Array(data)) };
}

export async function decryptPlayground(secret: string, packet: EncryptedPacket, maximumBytes = 256 * 1024): Promise<Uint8Array<ArrayBuffer>> {
  const iv = unbase64url(packet.iv, 12);
  if (iv.length !== 12) throw new Error("Invalid encrypted message nonce.");
  const ciphertext = unbase64url(packet.data, maximumBytes + 16);
  const bytes = await crypto.subtle.decrypt({ name: "AES-GCM", iv, additionalData }, await key(secret), ciphertext);
  if (bytes.byteLength > maximumBytes) throw new Error("Decoded source exceeds the Playground limit.");
  return new Uint8Array(bytes);
}

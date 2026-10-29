// Actual production Swift/WebCrypto interoperability, not a second crypto implementation.
// Requires macOS/Xcode and the site's installed esbuild. No real room credentials.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { createRequire } from "node:module";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const requireSite = createRequire(join(root, "site/package.json"));
const temporary = mkdtempSync(join(tmpdir(), "crabrix-runtime-crypto-"));
try {
  const bundle = join(temporary, "protocol.mjs");
  requireSite("esbuild").buildSync({ entryPoints: [join(root, "site/lib/playground-runtime-protocol.ts")], bundle: true, format: "esm", platform: "node", outfile: bundle });
  const { createRuntimeSigner, verifyRuntimeEnvelope } = await import(pathToFileURL(bundle).href);
  writeFileSync(join(temporary, "stub.swift"), "import Foundation\nstruct PlaygroundFailure: Error { init(_ message: String) {} }\n");
  writeFileSync(join(temporary, "main.swift"), `import Foundation
@main struct Probe {
 @MainActor static func main() throws {
  typealias Wire = PlaygroundRuntimeProtocol
  let capability = String(repeating: "A", count: 43)
  if CommandLine.arguments[1] == "sign" {
   let signer = PlaygroundRuntimeSigner()
   let fields = Wire.Fields(kind: "command", room: String(repeating: "a", count: 24), target: String(repeating: "b", count: 64), requestID: "signed-vector-0001", operation: "check", revision: String(repeating: "c", count: 64))
   let data = try signer.sign(fields, payload: Data("{\\"text\\":\\"CryptoKit → WebCrypto 🦀\\"}".utf8), editCapability: capability)
   print(String(data: data, encoding: .utf8)!)
   signer.destroy()
  } else {
   let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
   let frame = try Wire.verify(data, context: .init(room: String(repeating: "a", count: 24), target: String(repeating: "b", count: 64), editCapability: capability, requireEditProof: true))
   guard String(data: frame.payload, encoding: .utf8) == "{\\"text\\":\\"WebCrypto → CryptoKit 🦀\\"}" else { fatalError("Payload mismatch") }
   print("verified")
  }
 }
}
`);
  const binary = join(temporary, "probe");
  execFileSync("/usr/bin/xcrun", ["swiftc", "-swift-version", "6", "-parse-as-library", join(temporary, "stub.swift"), join(root, "Crabrix/Playground/PlaygroundEncryption.swift"), join(root, "Crabrix/Playground/PlaygroundRuntimeProtocol.swift"), join(temporary, "main.swift"), "-o", binary], { timeout: 60_000, stdio: "pipe" });
  const capability = "A".repeat(43), room = "a".repeat(24), target = "b".repeat(64);
  const signer = await createRuntimeSigner();
  try {
    const envelope = await signer.sign({ kind: "command", room, target, requestID: "signed-vector-0001", operation: "check", revision: "c".repeat(64) }, { text: "WebCrypto → CryptoKit 🦀" }, { editCapability: capability });
    const vector = join(temporary, "vector.json"); writeFileSync(vector, JSON.stringify(envelope));
    assert.equal(execFileSync(binary, ["verify", vector], { encoding: "utf8", timeout: 10_000 }).trim(), "verified");
    const native = JSON.parse(execFileSync(binary, ["sign"], { encoding: "utf8", timeout: 10_000 }));
    const frame = await verifyRuntimeEnvelope(native, { room, target, editCapability: capability, requireEditProof: true });
    assert.deepEqual(frame.payload, { text: "CryptoKit → WebCrypto 🦀" });
    assert.equal(Buffer.from(native.key, "base64url").length, 65);
    assert.equal(Buffer.from(native.signature, "base64url").length, 64);
    console.log("PASS production WebCrypto ↔ CryptoKit: raw keys/signatures, edit proofs, identities and Unicode payloads. This does not grant execution.");
  } finally { signer.destroy(); }
} finally { rmSync(temporary, { recursive: true, force: true }); }

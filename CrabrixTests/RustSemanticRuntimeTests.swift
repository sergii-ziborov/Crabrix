import XCTest
@testable import Crabrix

@MainActor
final class RustSemanticRuntimeTests: XCTestCase {
    private func payload(_ source: String, op: String, offset: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "workspace": ["files": [["path": "src/main.rs", "text": source]],
                          "crates": [["root": "src/main.rs", "name": "example"]]],
            "query": ["op": op, "file": "src/main.rs", "offset": offset],
        ])
    }
    private func result(_ bytes: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["ok"] as? Bool, true, String(data: bytes, encoding: .utf8) ?? "")
        return try XCTUnwrap(object["result"] as? [String: Any])
    }
    func testRealWorkerResolvesScopesAndUpdatesWithoutBlockingMainActor() async throws {
        let runtime = RustSemanticRuntime()
        defer { runtime.releaseMemory() }
        let source = "fn main(){let value=1;{let value=2;let x=value;}let y=value;}"
        let offset = try XCTUnwrap(source.range(of: "y=value")).lowerBound
        let bytes = try payload(source, op: "definition", offset: source[..<offset].utf8.count + 2)
        var ticks = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled { ticks += 1; do { try await Task.sleep(for: .milliseconds(20)) } catch { return } }
        }
        defer { heartbeat.cancel() }
        let response = try result(await runtime.perform(bytes))
        let targets = try XCTUnwrap(response["targets"] as? [[String: Any]])
        let range = try XCTUnwrap(targets.first?["range"] as? [String: Any])
        XCTAssertEqual(range["start"] as? Int, try XCTUnwrap(source.range(of: "value=1")).lowerBound.utf16Offset(in: source))
        XCTAssertGreaterThan(ticks, 1, "The UIKit main actor must keep running while analyzing.")
        let changed = source.replacingOccurrences(of: "value=1", with: "value=true")
        let at = try XCTUnwrap(changed.range(of: "y=value")).lowerBound
        let hovered = try result(await runtime.perform(payload(changed, op: "hover", offset: changed[..<at].utf8.count + 2)))
        XCTAssertTrue((hovered["hover"] as? [String: Any])?["text"].map { String(describing: $0).contains("bool") } == true)
    }
    func testRealStandardLibraryCompletionUsesTheReceiverType() async throws {
        let runtime = RustSemanticRuntime()
        defer { runtime.releaseMemory() }
        for (source, token, expected, rejected) in [
            ("fn main(){let mut values=vec![1_i32,2];values.pu;}", "values.pu", "push", "push_str"),
            ("fn main(){let mut text=String::from(\"Ada\");text.push_;}", "text.push_", "push_str", "iter"),
            ("struct Person;impl Person{fn greet(&self){}}fn main(){let p=Person;p.gr;}", "p.gr", "greet", "iter"),
        ] {
            let at = try XCTUnwrap(source.range(of: token)).upperBound
            let response = try result(await runtime.perform(payload(source, op: "complete", offset: source[..<at].utf8.count)))
            let items = try XCTUnwrap(response["items"] as? [[String: Any]])
            let labels = items.compactMap { $0["label"] as? String }
            XCTAssertTrue(labels.contains(expected), labels.joined(separator: ", "))
            XCTAssertFalse(labels.contains(rejected), "Methods cannot be guessed from a trailing dot.")
        }
    }
}

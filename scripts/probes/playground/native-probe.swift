import Foundation
@main struct NativeProbe {
    @MainActor static func main() async throws {
        var session: PlaygroundLiveSession?
        let codec = URL(fileURLWithPath: CommandLine.arguments[1])
        let origin = URL(string: CommandLine.arguments[2])!
        func emit(_ value: [String: Any]) { let bytes = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]); FileHandle.standardOutput.write(bytes + Data([10])) }
        let commands = AsyncStream<String> { continuation in
            Thread.detachNewThread { while let line = readLine() { continuation.yield(line) }; continuation.finish() }
        }
        for await line in commands {
            do {
                let command = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                let type = command["type"] as! String
                if type == "create" {
                    let source = try JSONDecoder().decode(PlaygroundDocument.self, from: JSONSerialization.data(withJSONObject: command["document"]!))
                    session = try await PlaygroundLiveSession.create(document: source, lifetimeSeconds: 3600, origin: origin, codecURL: codec)
                } else if type == "join" {
                    let value = command["link"] as! [String: Any]
                    let link = PlaygroundLink(id: value["id"] as! String, key: value["key"] as! String, access: value["access"] as! String, expiresAt: Date(timeIntervalSince1970: (value["expiresAt"] as! Double) / 1000), isReadOnly: value["mode"] as? String == "view")
                    session = try PlaygroundLiveSession(link: link, origin: origin, codecURL: codec)
                } else if type == "edit" { session?.edit(file: command["file"] as! String, text: command["text"] as! String); continue }
                else if type == "selection" { session?.select(file: command["file"] as! String, range: NSRange(location: command["anchor"] as! Int, length: command["length"] as! Int)); continue }
                else if type == "stop" { session?.stop(); emit(["event": "stopped"]); continue }
                else if type == "exit" { session?.stop(); return }
                if let session {
                    session.onDocument = { document in emit(["event": "document", "document": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(document))]) }
                    session.onSelections = { selections in emit(["event": "selections", "selections": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(selections))]) }
                    session.onStatus = { status in emit(["event": "status", "status": status]) }
                    let link = session.link
                    emit(["event": "ready", "link": ["id": link.id, "key": link.key, "access": link.access, "expiresAt": link.expiresAt.timeIntervalSince1970 * 1000, "mode": link.isReadOnly ? "view" : "edit"]])
                    session.start()
                }
            } catch { emit(["event": "error", "error": error.localizedDescription]) }
        }
    }
}

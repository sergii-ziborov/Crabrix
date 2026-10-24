import Foundation
import XCTest
import WasmKitWASI
@testable import Crabrix

final class WasmProceduralMacroTests: XCTestCase {
    func testLoaderAcceptsOnlyDeclaredFilesInsideTheGrantedArtifactDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MacroAdmission-\(UUID())")
        let artifacts = root.appending(path: "artifacts")
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inside = artifacts.appending(path: "macro.wasm")
        let outside = root.appending(path: "outside.wasm")
        let bytes = Data([0, 97, 115, 109, 1, 0, 0, 0])
        try bytes.write(to: inside); try bytes.write(to: outside)
        let preopens = [WASIBridgeToHost.Preopen(guestPath: "/artifacts", hostPath: artifacts.path)]
        XCTAssertEqual(try WasmProceduralMacroSession.artifactURL("/artifacts/macro.wasm",
            allowed: ["/artifacts/macro.wasm"], preopens: preopens), inside.resolvingSymlinksInPath())
        XCTAssertThrowsError(try WasmProceduralMacroSession.artifactURL("/artifacts/macro.wasm", allowed: [], preopens: preopens))
        XCTAssertThrowsError(try WasmProceduralMacroSession.artifactURL("/artifacts/../outside.wasm",
            allowed: ["/artifacts/../outside.wasm"], preopens: preopens))
        let link = artifacts.appending(path: "escaped.wasm")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try WasmProceduralMacroSession.artifactURL("/artifacts/escaped.wasm",
            allowed: ["/artifacts/escaped.wasm"], preopens: preopens))
    }

    func testCheckLinksMacroArtifactsAndTheirLibraries() {
        let macro = CargoExtern(alias: "derive", crateName: "derive", fingerprint: "0123456789abcdef",
                                isProceduralMacro: true, requiresLink: true)
        let support = CargoExtern(alias: "syn", crateName: "syn", fingerprint: "fedcba9876543210", requiresLink: true)
        XCTAssertEqual(macro.fileName(emit: .metadata), "derive-0123456789abcdef.wasm")
        XCTAssertEqual(support.fileName(emit: .metadata), "libsyn-fedcba9876543210.rlib")
        XCTAssertEqual(CargoExtern(alias: "plain", crateName: "plain", fingerprint: "0123456789abcdef")
            .fileName(emit: .metadata), "libplain-0123456789abcdef.rmeta")
    }
}

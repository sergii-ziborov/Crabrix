import XCTest
import UIKit

@MainActor
final class PlaygroundRuntimeUITests: XCTestCase {
    func testSharedMCPRuntimeThroughActualPermissionUIAndExistingEditor() async throws {
        struct Fixture: Decodable { let url: URL; let nonce: String; let origin: URL }
        let coordinator = URL(string: "http://127.0.0.1:3395")!
        let (data, _) = try await URLSession.shared.data(from: coordinator.appendingPathComponent("fixture"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        let pad = UIDevice.current.userInterfaceIdiom == .pad, role = pad ? "pad" : "phone"
        func report(_ event: String) async throws {
            var request = URLRequest(url: coordinator.appendingPathComponent("event")); request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: ["role":role,"event":event]); request.setValue("application/json", forHTTPHeaderField:"Content-Type")
            _ = try await URLSession.shared.data(for: request)
        }
        let app = XCUIApplication(); app.launchArguments = ["--crabrix-playground-relay=\(fixture.origin.absoluteString)","-crabrix.appearance",pad ? "cyberpunkNeon" : "dark"]
        app.launch()
        let native = fixture.url.absoluteString.replacingOccurrences(of: fixture.origin.absoluteString + "/playground/", with:"crabrix://playground/")
        app.open(try XCTUnwrap(URL(string:native)))
        let editor = app.textViews["Source code editor"]
        XCTAssertTrue(editor.waitForExistence(timeout:60))
        func waitSource(_ text: String) async throws {
            let end=Date().addingTimeInterval(120)
            while !(editor.value as? String ?? "").contains(text) { if Date()>end { throw NSError(domain:"RuntimeUI",code:1,userInfo:[NSLocalizedDescriptionKey:"Shared source did not converge: \(text)"]) };try await Task.sleep(for:.milliseconds(200)) }
        }
        try await waitSource(fixture.nonce)
        if pad { try await waitSource("from-phone") }
        editor.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:110,dy:20)).tap()
        editor.typeText(" from-\(role) ")
        if let hide=app.buttons.matching(identifier:"Hide keyboard").allElementsBoundByIndex.first(where:{$0.isHittable}){hide.tap()}
        try await report("opened-edited")
        let direct=app.buttons["Project settings and share"]
        if direct.exists&&direct.isHittable { direct.tap() }
        else {
            let menu=app.buttons["Project menu"].exists ? app.buttons["Project menu"] : app.buttons["PROJECT"]
            XCTAssertTrue(menu.waitForExistence(timeout:15)); menu.tap()
            let details=app.buttons["Project Details & Share"].exists ? app.buttons["Project Details & Share"] : app.buttons["Project settings and share"]
            details.tap()
        }
        let share=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Share a Playground")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout:20))
        for _ in 0..<10 {if share.isHittable{break};app.swipeUp()};share.tap()
        let allow=app.buttons["Allow selected operations · 10 min"]
        XCTAssertTrue(allow.waitForExistence(timeout:120))
        for _ in 0..<14 {if allow.isHittable{break};app.swipeUp()}
        let before=XCTAttachment(screenshot:XCUIScreen.main.screenshot());before.name="runtime-\(role)-permission";before.lifetime = .keepAlways;add(before)
        XCTAssertTrue(allow.isHittable);allow.tap();try await report("permission-allowed")
        app.buttons["Close Playground sharing"].tap()
        for tab in ["code","problems","output","terminal"] { XCTAssertTrue(app.buttons["build-dock-\(tab)"].exists,"Original editor panel missing: \(tab)") }
        app.buttons["build-dock-output"].tap()
        let end=Date().addingTimeInterval(720)
        var observed=Set<String>()
        while Date()<end {
            let (data,_)=try await URLSession.shared.data(from:coordinator.appendingPathComponent("phase"))
            let phase=(try JSONSerialization.jsonObject(with:data) as? [String:String])?["phase"] ?? ""
            if phase=="complete" { break }
            if phase.hasPrefix("output-") {
                let outputID=String(phase.dropFirst(7))
                let executing=outputID.split(separator:"-").last.map(String.init) ?? outputID
                if executing != role && !observed.contains(phase) {
                    app.buttons["build-dock-output"].tap()
                    let preview=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","Shared output from ")).firstMatch
                    guard preview.waitForExistence(timeout:30) else { throw NSError(domain:"RuntimeUI",code:2,userInfo:[NSLocalizedDescriptionKey:"Other participant output was not visible in Output"]) }
                    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","no code ran on this device")).firstMatch.exists)
                    observed.insert(phase);try await report("mirrored-"+outputID)
                }
            }
            if phase=="manual-phone" && role=="phone" && !observed.contains(phase) {
                observed.insert(phase)
                let run=app.buttons["Run project"];XCTAssertTrue(run.waitForExistence(timeout:15));run.tap();try await report("manual-run-started")
            }
            if phase=="verified-\(role)" && !observed.contains(phase) {
                observed.insert(phase)
                app.buttons["build-dock-output"].tap()
                let after=XCTAttachment(screenshot:XCUIScreen.main.screenshot());after.name="runtime-\(role)-output";after.lifetime = .keepAlways;add(after)
                try await report("ui-verified")
            }
            try await Task.sleep(for:.seconds(1))
        }
        XCTAssertLessThan(Date(),end,"Controller did not finish the local execution and passive output matrix")
        XCTAssertTrue(observed.contains("verified-"+role))
        XCTAssertEqual(observed.filter{$0.hasPrefix("output-")}.count,pad ? 4 : 3)

    }
}

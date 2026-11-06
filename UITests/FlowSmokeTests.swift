// SPDX-License-Identifier: GPL-3.0-only
import XCTest

final class FlowSmokeTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func addVideo(_ app: XCUIApplication, title: String) {
        app.buttons["Add video"].tap()
        let link = app.textFields["YouTube link"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap(); link.typeText("https://www.youtube.com/watch?v=jNQXAC9IVRw")
        let name = app.textFields["Title (optional)"]
        name.tap(); name.typeText(title)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Flow Prototype"].waitForExistence(timeout: 10))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLibraryLaunchCancelAndPersistence() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Add video"].waitForExistence(timeout: 15))
        app.buttons["Add video"].tap()
        XCTAssertTrue(app.textFields["YouTube link"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Flow Prototype"].waitForExistence(timeout: 10))
        addVideo(app, title: "Smoke test public video")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Add video"].waitForExistence(timeout: 15))
        let saved = app.staticTexts["Smoke test public video"]
        reveal(saved, in: app)
        XCTAssertTrue(saved.exists, "Saved bookmark must survive app restart")
        capture(app, name: "Library after restart")
    }

    func testObserveOfficialEmbeddedPlayer() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Add video"].waitForExistence(timeout: 15))
        addVideo(app, title: "Public video playback observation")
        let saved = app.staticTexts["Public video playback observation"]
        reveal(saved, in: app)
        XCTAssertTrue(saved.isHittable); saved.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        // A single normal Play interaction, only if the official UI exposes it.
        // No retries, alternate identities, login, consent or restriction bypass.
        let play = app.webViews.buttons.matching(NSPredicate(format: "label == 'Play' OR label == 'Play video'")).firstMatch
        let playExposed = play.waitForExistence(timeout: 20)
        capture(app, name: "Official player before interaction")
        print("OFFICIAL_PLAYER_PLAY_CONTROL_EXPOSED=\(playExposed)")
        if playExposed && play.isHittable { play.tap() }
        Thread.sleep(forTimeInterval: 5)
        capture(app, name: "Official player observation at 5 seconds")
        print("OFFICIAL_PLAYER_UI_AT_5_SECONDS\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 5)
        capture(app, name: "Official player observation at 10 seconds")
        print("OFFICIAL_PLAYER_UI_AT_10_SECONDS\n\(app.debugDescription)")
        // Passing this observation test means the screen was reached, not playback success.
    }
}

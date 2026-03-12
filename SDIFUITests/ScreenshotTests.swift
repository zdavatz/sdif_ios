import XCTest

final class ScreenshotTests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    private func tapTab(_ name: String) {
        // iPhone uses tabBars, iPad uses a toolbar/sidebar
        let tabButton = app.tabBars.buttons[name]
        if tabButton.exists {
            tabButton.tap()
        } else {
            // iPad: try buttons anywhere
            let button = app.buttons[name]
            if button.waitForExistence(timeout: 3) {
                button.tap()
            }
        }
    }

    func testGenerateScreenshots() throws {
        let screenshotDir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? "/tmp/sdif_screenshots"

        // Tab 1: Interaktions-Check — search and add Aspirin
        let searchField1 = app.textFields.firstMatch
        XCTAssertTrue(searchField1.waitForExistence(timeout: 5))
        searchField1.tap()
        searchField1.typeText("Aspirin")
        sleep(3)

        // Screenshot: search suggestions
        saveScreenshot(name: "01_suche_aspirin", dir: screenshotDir)

        // Tap first suggestion to add to basket
        let firstSuggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Aspirin'")).firstMatch
        if firstSuggestion.waitForExistence(timeout: 3) {
            firstSuggestion.tap()
            sleep(1)
        }

        // Search for Marcoumar
        let searchField1b = app.textFields.firstMatch
        searchField1b.tap()
        searchField1b.typeText("Marcoumar")
        sleep(3)

        // Tap first Marcoumar suggestion
        let marcoumarSuggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Marcoumar'")).firstMatch
        if marcoumarSuggestion.waitForExistence(timeout: 3) {
            marcoumarSuggestion.tap()
            sleep(3)
        }

        // Screenshot: interaction results
        saveScreenshot(name: "02_interaktionen", dir: screenshotDir)

        // Tab 2: Klinische Suche
        tapTab("Klinische Suche")
        sleep(1)

        let searchField2 = app.textFields.firstMatch
        XCTAssertTrue(searchField2.waitForExistence(timeout: 5))
        searchField2.tap()
        searchField2.typeText("QT")
        sleep(3)

        // Screenshot: clinical search suggestions
        saveScreenshot(name: "03_klinische_suche_vorschlaege", dir: screenshotDir)

        // Tap first suggestion to search
        let qtSuggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'QT'")).firstMatch
        if qtSuggestion.waitForExistence(timeout: 3) {
            qtSuggestion.tap()
            sleep(3)
        }

        // Screenshot: clinical search results
        saveScreenshot(name: "04_klinische_suche_resultate", dir: screenshotDir)

        // Tab 3: ATC-Klassen
        tapTab("ATC-Klassen")
        // Wait until loading spinner disappears (heavy computation)
        let loadingText = app.staticTexts["ATC-Klassen werden analysiert..."]
        if loadingText.waitForExistence(timeout: 5) {
            let disappeared = NSPredicate(format: "exists == false")
            expectation(for: disappeared, evaluatedWith: loadingText)
            waitForExpectations(timeout: 120)
        }
        sleep(2)

        // Screenshot: ATC class table
        saveScreenshot(name: "05_atc_klassen", dir: screenshotDir)

        // Settings
        let iconButton = app.navigationBars.buttons.firstMatch
        if iconButton.waitForExistence(timeout: 3) {
            iconButton.tap()
            sleep(1)
            saveScreenshot(name: "06_einstellungen", dir: screenshotDir)
        }
    }

    private func saveScreenshot(name: String, dir: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/\(name).png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
    }
}

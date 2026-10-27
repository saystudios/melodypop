import XCTest

final class MelodyPopUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// iPhone shows a bottom tab bar; iPadOS 18 shows tabs at the top as plain buttons.
    private func openTab(_ name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 5) {
            tab.tap()
        } else {
            app.buttons[name].firstMatch.tap()
        }
    }

    private func launch(student: String? = "Mia", skipModeSelection: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        if skipModeSelection { app.launchArguments.append("-uitest-skip-mode-selection") }
        if let student { app.launchArguments += ["-uitest-student", student] }
        app.launch()
        return app
    }

    func testOnboardingCreatesProfileAndShowsModeSelection() {
        let app = launch(student: nil, skipModeSelection: false)
        let name = app.textFields["profile-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Leo")
        app.buttons["create-profile"].tap()
        XCTAssertTrue(app.buttons["select-mode-microphone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["select-mode-midi"].exists)
        XCTAssertTrue(app.buttons["select-mode-touch"].exists)
        app.buttons["select-mode-touch"].tap()
        app.buttons["start-learning"].tap()
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hi, Leo!"].exists)
    }

    func testVirtualPianoPlaysHighlightsRecordsAndPlaysBack() {
        let app = launch()
        openTab("Piano", in: app)
        let middleC = app.otherElements["key-60"]
        XCTAssertTrue(middleC.waitForExistence(timeout: 10), "Middle C should be visible on the keyboard")

        middleC.tap()
        XCTAssertTrue(app.staticTexts["Last note: C4"].waitForExistence(timeout: 3))

        // Octave shifting moves the visible range.
        let range = app.staticTexts["keyboard-range"]
        let before = range.label
        app.buttons["octave-up"].tap()
        XCTAssertNotEqual(range.label, before)
        XCTAssertTrue(app.otherElements["key-72"].waitForExistence(timeout: 3))
        app.otherElements["key-72"].tap()
        XCTAssertTrue(app.staticTexts["Last note: C5"].waitForExistence(timeout: 3))
        app.buttons["octave-down"].tap()

        // Record a short phrase, then play it back.
        app.buttons["record-button"].tap()
        for key in ["key-60", "key-62", "key-64"] {
            app.otherElements[key].tap()
        }
        app.buttons["stop-recording"].tap()
        let playBack = app.buttons["play-recording"]
        XCTAssertTrue(playBack.waitForExistence(timeout: 3))
        playBack.tap()
        XCTAssertTrue(app.buttons["stop-playback"].waitForExistence(timeout: 3))
        // Playback finishes on its own.
        XCTAssertTrue(playBack.waitForExistence(timeout: 10))
        app.buttons["save-recording"].tap()
        XCTAssertTrue(app.staticTexts["saved-message"].waitForExistence(timeout: 3))
    }

    func testLessonOneWithVirtualPianoAndModeSwitching() {
        let app = launch()
        let lesson = app.buttons["lesson-1"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        lesson.tap()

        XCTAssertTrue(app.buttons["mode-touch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode-microphone"].exists)
        XCTAssertTrue(app.buttons["mode-midi"].exists)
        app.buttons["start-button"].tap()

        let progress = app.staticTexts["progress-label"]
        let middleC = app.otherElements["key-60"]
        XCTAssertTrue(middleC.waitForExistence(timeout: 5))
        middleC.tap()
        middleC.tap()
        XCTAssertEqual(progress.label, "2 of 7")

        // A wrong note does not advance.
        app.otherElements["key-62"].tap()
        XCTAssertEqual(progress.label, "2 of 7")

        // Switch to Connect My Keyboard mid-lesson, then back: progress is kept.
        app.buttons["mode-midi"].tap()
        XCTAssertEqual(progress.label, "2 of 7")
        app.buttons["mode-touch"].tap()
        let resume = app.buttons["resume-button"]
        if resume.waitForExistence(timeout: 2) { resume.tap() }
        XCTAssertEqual(progress.label, "2 of 7")

        for _ in 0..<5 { app.otherElements["key-60"].tap() }

        let accuracy = app.staticTexts["result-accuracy"]
        XCTAssertTrue(accuracy.waitForExistence(timeout: 5))
        // 6 perfect + 1 note with one mistake (graded "good" = 0.85) → (6 + 0.85) / 7 = 98%.
        XCTAssertEqual(accuracy.label, "98%")
        app.buttons["result-done"].tap()
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 5))
    }

    func testSongPracticeRunsTimedScoring() {
        let app = launch()
        openTab("Songs", in: app)
        let song = app.buttons["song-104"] // Hot Cross Buns (free)
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        song.tap()
        XCTAssertTrue(app.buttons["tempo-menu"].waitForExistence(timeout: 5))
        app.buttons["start-button"].tap()
        XCTAssertTrue(app.staticTexts["count-in"].waitForExistence(timeout: 3))
        // Pause and resume keep the run going.
        app.buttons["pause-button"].tap()
        XCTAssertTrue(app.buttons["resume-button"].waitForExistence(timeout: 2))
        app.buttons["resume-button"].tap()
        // Nobody plays: every note is missed and scored as such.
        let accuracy = app.staticTexts["result-accuracy"]
        if !accuracy.waitForExistence(timeout: 30) {
            let progress = app.staticTexts["progress-label"]
            let state = progress.exists ? progress.label : "no progress label"
            let mainButton = ["start-button", "pause-button", "resume-button"].first { app.buttons[$0].exists } ?? "none"
            XCTFail("Song never finished. Progress: \(state); main button: \(mainButton); paused reason: \(app.staticTexts["paused-reason"].exists ? app.staticTexts["paused-reason"].label : "none")")
            return
        }
        XCTAssertEqual(accuracy.label, "0%")
        app.buttons["result-retry"].tap()
        XCTAssertTrue(app.staticTexts["count-in"].waitForExistence(timeout: 3))
    }

    func testKeyFinderGameScores() {
        let app = launch()
        openTab("Games", in: app)
        app.buttons["game-keyFinder"].tap()
        app.buttons["game-start"].tap()
        let letter = app.staticTexts["game-letter"]
        XCTAssertTrue(letter.waitForExistence(timeout: 5))
        let names = ["C": 60, "D": 62, "E": 64, "F": 65, "G": 67, "A": 69, "B": 71]
        let midi = names[letter.label]!
        app.otherElements["key-\(midi)"].tap()
        let score = app.staticTexts["game-score"]
        XCTAssertTrue(score.waitForExistence(timeout: 2))
        XCTAssertNotEqual(score.label, "0")
    }

    func testParentDashboardBehindGate() {
        let app = launch()
        openTab("Me", in: app)
        app.buttons["open-parents"].tap()
        let q = app.staticTexts["gate-question"]
        XCTAssertTrue(q.waitForExistence(timeout: 5))
        // "What is 7 × 8?"
        let numbers = q.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        XCTAssertEqual(numbers.count, 2)
        let field = app.textFields["gate-answer"]
        field.tap()
        field.typeText(String(numbers[0] * numbers[1]))
        app.buttons["gate-continue"].tap()
        XCTAssertTrue(app.otherElements["parent-summary"].waitForExistence(timeout: 5) || app.staticTexts["Practice this week"].waitForExistence(timeout: 2))
    }
}


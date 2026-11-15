import XCTest

final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testMapOverview() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["reportButton"].waitForExistence(timeout: 30))
        sleep(8)
        snap("00-map", app)
    }

    @MainActor
    func testCameraCard() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-km.openCamera", "13"]
        app.launch()
        XCTAssertTrue(app.buttons["reportButton"].waitForExistence(timeout: 30))
        sleep(8)
        snap("01-camera-card", app)
        app.swipeUp()
        sleep(2)
        snap("02-camera-card-full", app)
    }

    @MainActor
    func testLoginReportAndProfile() throws {
        let app = XCUIApplication()
        app.launch()

        let account = app.buttons["accountButton"]
        XCTAssertTrue(account.waitForExistence(timeout: 30))
        account.tap()

        let phone = app.textFields["phoneField"]
        if phone.waitForExistence(timeout: 5) {
            phone.tap()
            phone.typeText("900000002")
            snap("10-login-phone", app)
            app.buttons["requestCodeButton"].tap()

            let shown = app.staticTexts["shownCode"]
            XCTAssertTrue(shown.waitForExistence(timeout: 20))
            snap("11-login-code", app)

            let digits = String(shown.label.filter(\.isNumber).suffix(6))
            let codeField = app.textFields["codeField"]
            codeField.tap()
            codeField.typeText(digits)

            let name = app.textFields["nameField"]
            if name.exists {
                name.tap()
                name.typeText("CI Tester")
            }
            app.buttons["signInButton"].tap()
        } else if app.buttons["Готово"].exists {
            app.buttons["Готово"].tap()
        }

        let report = app.buttons["reportButton"]
        XCTAssertTrue(report.waitForExistence(timeout: 20))
        sleep(2)
        report.tap()
        XCTAssertTrue(app.buttons["chooseLocationButton"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "ДПС")).firstMatch.tap()
        snap("20-report-types", app)

        app.buttons["chooseLocationButton"].tap()
        allowLocationIfAsked()
        sleep(4)
        snap("21-report-placement", app)

        if app.buttons["Отмена"].exists {
            app.buttons["Отмена"].tap()
        }
        sleep(1)

        account.tap()
        sleep(2)
        snap("30-profile", app)
    }

    @MainActor
    private func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 4) {
            for title in ["Allow While Using App", "Allow Once", "При использовании", "Разрешить один раз"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return
                }
            }
        }
    }

    @MainActor
    private func snap(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

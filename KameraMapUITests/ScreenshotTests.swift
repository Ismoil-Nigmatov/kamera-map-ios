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
        let sheetTop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64))
        sheetTop.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)))
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
            let name = app.textFields["nameField"]
            let isNewUser = name.exists
            let codeField = app.textFields["codeField"]
            codeField.tap()
            codeField.typeText(digits)

            if isNewUser {
                name.tap()
                name.typeText("CI Tester")
                app.buttons["signInButton"].tap()
            }
        } else if app.buttons["Готово"].exists {
            app.buttons["Готово"].tap()
        }

        let tripButton = app.buttons["tripButton"]
        XCTAssertTrue(tripButton.waitForExistence(timeout: 20))
        sleep(1)
        tripButton.tap()
        let share = app.buttons["shareAndStartButton"]
        if share.waitForExistence(timeout: 8) {
            snap("15-trip-consent", app)
            share.tap()
        }
        allowLocationIfAsked()
        let sent = app.staticTexts
            .matching(NSPredicate(format: "identifier == %@ AND label MATCHES %@", "tripStatus", ".*отправлено точек: [1-9][0-9]*"))
            .firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 45))
        snap("16-trip", app)
        app.buttons["stopTripButton"].tap()

        let report = app.buttons["reportButton"]
        XCTAssertTrue(report.waitForExistence(timeout: 20))
        sleep(2)
        report.tap()
        XCTAssertTrue(app.buttons["chooseLocationButton"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "ДПС")).firstMatch.tap()
        snap("20-report-types", app)

        app.buttons["chooseLocationButton"].tap()
        allowLocationIfAsked()
        XCTAssertTrue(app.buttons["placeHereButton"].waitForExistence(timeout: 5))
        sleep(2)
        snap("21-report-placement", app)

        if app.buttons["Отмена"].exists {
            app.buttons["Отмена"].tap()
        }
        sleep(1)

        account.tap()
        sleep(2)
        snap("30-profile", app)

        let deleteRow = app.buttons["deleteAccountButton"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 5))
        deleteRow.tap()
        let confirm = app.buttons
            .matching(NSPredicate(format: "label == %@ AND identifier != %@", "Удалить аккаунт", "deleteAccountButton"))
            .firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["Войти"].waitForExistence(timeout: 15))
        snap("31-signed-out", app)
    }

    @MainActor
    private func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else { return }
        let allow = alert.buttons
            .matching(NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "While Using", "использовании", "Allow Once", "один раз"
            ))
            .firstMatch
        if allow.exists {
            allow.tap()
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

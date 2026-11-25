import StoreKitTest
import XCTest

final class ReadingFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPagingAndPrivateReadingDataSurviveRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LIUBAI_UI_TEST_LIBRARY"] = UUID().uuidString
        app.launchArguments = ["-appearance", "light"]
        app.launch()

        let feed = app.scrollViews["reading.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 8))
        capture("01-阅读首页", app)
        feed.swipeUp()
        let secondCover = app.buttons["reading.cover.circle-of-choice"]
        XCTAssertTrue(secondCover.waitForExistence(timeout: 5))
        XCTAssertTrue(secondCover.isHittable)
        secondCover.tap()

        XCTAssertTrue(app.staticTexts["分清你能决定的事"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "AI 生成")).firstMatch.exists)
        capture("02-Markdown正文", app)
        let content = app.scrollViews["article.content"]
        content.swipeUp()
        XCTAssertTrue(app.staticTexts["写给自己"].exists)

        let like = app.buttons["article.like"]
        like.tap()
        XCTAssertEqual(like.label, "取消喜欢")
        app.buttons["article.collect"].tap()
        app.buttons["collection.create"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Read again")
        app.alerts.buttons["创建并收藏"].tap()
        XCTAssertTrue(app.staticTexts["Read again"].waitForExistence(timeout: 5))
        app.buttons["collection.done"].tap()

        app.buttons["article.note"].tap()
        let editor = app.textViews["note.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        app.buttons["note.format.bold"].tap()
        editor.typeText("Focus")
        app.buttons["note.format.underline"].tap()
        editor.typeText(" today")
        editor.typeText("\n")
        app.buttons["note.format.numbers"].tap()
        editor.typeText("One\nTwo")
        capture("03-富文本笔记", app)
        app.buttons["note.save"].tap()
        XCTAssertTrue(app.buttons["article.note"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()

        app.tabBars.buttons["书架"].tap()
        XCTAssertTrue(app.staticTexts["Read again"].waitForExistence(timeout: 5))
        app.buttons["喜欢"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "分清你能决定的事")).firstMatch.exists)
        app.buttons["笔记"].tap()
        let preview = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Focus today")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        XCTAssertEqual(app.textViews["note.text"].value as? String, "Focus today\nOne\nTwo")
        capture("04-重启后的笔记", app)
    }

    func testDarkModeAndStoreKitTip() throws {
        let store = try SKTestSession(configurationFileNamed: "Tips")
        store.resetToDefaultState()
        store.clearTransactions()
        store.disableDialogs = true

        let app = XCUIApplication()
        app.launchEnvironment["LIUBAI_UI_TEST_LIBRARY"] = UUID().uuidString
        app.launchArguments = ["-appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["reading.open"].firstMatch.waitForExistence(timeout: 8))
        capture("05-深色首页", app)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.import"].exists)
        XCTAssertTrue(app.buttons["settings.export"].exists)
        capture("06-设置", app)
        app.buttons["settings.tip"].tap()
        let tip = app.buttons["app.liubai.reader.tip.small"]
        XCTAssertTrue(tip.waitForExistence(timeout: 12))
        tip.tap()
        XCTAssertTrue(app.alerts.staticTexts["谢谢你支持留白。"].waitForExistence(timeout: 10))
        XCTAssertEqual(store.allTransactions().first?.productIdentifier, "app.liubai.reader.tip.small")
    }

    func testBackupFileRoundTrip() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LIUBAI_UI_TEST_LIBRARY"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let like = app.buttons["article.like"].firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 8))
        like.tap()
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.export"].tap()
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8), app.debugDescription)
        if !save.isEnabled {
            let phone = app.buttons["On My iPhone"].firstMatch
            XCTAssertTrue(phone.exists, app.debugDescription)
            phone.tap()
        }
        save.tap()
        let replace = app.alerts.buttons["Replace"].firstMatch
        if replace.waitForExistence(timeout: 2) { replace.tap() }
        let exported = app.alerts.staticTexts["备份已导出。"]
        XCTAssertTrue(exported.waitForExistence(timeout: 8), app.debugDescription)
        app.alerts.buttons["好"].tap()

        app.tabBars.buttons["阅读"].tap()
        like.tap()
        XCTAssertEqual(like.label, "喜欢")
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.import"].tap()
        let file = app.cells.containing(NSPredicate(format: "identifier BEGINSWITH %@", "留白备份")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 8), app.debugDescription)
        file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.27)).tap()
        let imported = app.alerts.staticTexts["备份已导入，喜欢、收藏和笔记已合并。"]
        XCTAssertTrue(imported.waitForExistence(timeout: 8), app.debugDescription)
        app.alerts.buttons["好"].tap()
        app.tabBars.buttons["阅读"].tap()
        XCTAssertEqual(like.label, "取消喜欢")
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

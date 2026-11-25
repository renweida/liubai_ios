import StoreKitTest
import XCTest

final class ReadingFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPagingAndPrivateReadingDataSurviveRelaunch() throws {
        let app = readingApp()
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

        let app = readingApp()
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
        let app = readingApp()
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

    func testStyleConfirmationReordersUpcomingArticlesAndPersists() {
        let app = readingApp()
        app.launch()

        let current = app.buttons["reading.cover.return-to-now"]
        let style = app.buttons["reading.style"]
        XCTAssertTrue(current.waitForExistence(timeout: 8))
        XCTAssertEqual(style.value as? String, "均衡阅读")
        XCTAssertFalse(app.staticTexts["1 / 5"].exists)

        style.tap()
        let psychology = app.buttons["reading.style.psychology"]
        XCTAssertTrue(psychology.waitForExistence(timeout: 5))
        psychology.tap()
        app.buttons["reading.style.cancel"].tap()
        XCTAssertEqual(style.value as? String, "均衡阅读")

        style.tap()
        psychology.tap()
        app.buttons["reading.style.confirm"].tap()
        XCTAssertEqual(style.value as? String, "心理觉察")
        XCTAssertTrue(current.isHittable)

        app.scrollViews["reading.feed"].swipeUp()
        let preferred = app.buttons["reading.cover.name-the-feeling"]
        XCTAssertTrue(preferred.waitForExistence(timeout: 5))
        XCTAssertTrue(preferred.isHittable)
        app.buttons["reading.next"].tap()
        app.buttons["reading.next"].tap()
        XCTAssertTrue(app.buttons["reading.cover.circle-of-choice"].isHittable)

        app.terminate()
        app.launch()
        XCTAssertTrue(style.waitForExistence(timeout: 8))
        XCTAssertEqual(style.value as? String, "心理觉察")
    }

    func testEmptyResponseOffersRetryWithoutBundledArticles() {
        let app = readingApp(response: "[]")
        app.launch()

        XCTAssertTrue(app.staticTexts["暂时没有文章"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["reading.open"].firstMatch.exists)
        app.buttons["reading.retry"].tap()
        XCTAssertTrue(app.staticTexts["暂时没有文章"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reading.open"].firstMatch.exists)
    }

    private func readingApp(response: String = testArticleResponse) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LIUBAI_UI_TEST_LIBRARY"] = UUID().uuidString
        app.launchEnvironment["LIUBAI_UI_TEST_ARTICLES"] = Data(response.utf8).base64EncodedString()
        return app
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private let testArticleResponse = #"""
[
  {"id": "return-to-now", "category": "心理学", "theme": "当下", "title": "把自己带回", "subtitle": "此刻", "excerpt": "当思绪跑得太远，试着回到眼前这件小事。", "minutes": 3, "markdown": "## 写给自己\n\n当我的注意力离开此刻时，它最常去哪里？今天，有什么小事让我愿意停下来多看一眼？", "source": "AI 生成"},
  {"id": "circle-of-choice", "category": "哲学", "theme": "选择", "title": "分清你能", "subtitle": "决定的事", "excerpt": "在结果之外，重新看见手里还有哪些选择。", "minutes": 4, "markdown": "发出一条重要消息之后，最难熬的也许是等待。我们会一遍遍点亮屏幕，揣测那头正在发生什么。越想知道答案，手里的时间越容易被等待拿走。\n\n## 两种范围\n\n斯多葛哲学里有一个朴素的区分。爱比克泰德在《手册》开篇谈到，有些事取决于我们，比如判断和行动。有些事也受外界左右，比如别人怎样评价我们。\n\n这个区分尤其适合用在结果悬而未决的时候。你可以认真措辞、如实表达，也可以约定一个合适的跟进时间。直到对方回复之前，这些行动都已经有了自己的价值。\n\n> 把心力还给那些目前可以采取的行动。\n\n## 把烦恼写下来\n\n- 写下一件最近让你反复惦记的事。\n- 圈出一句由「我可以」开头、今天能够完成的话。\n- 给暂时无法决定的部分留一点空白，晚些再回来看看。\n\n你也可以把原本要花在刷新消息上的五分钟，用来做一件独立于结果的事。例如伸展一下、走到窗边，或者把今天的晚餐好好吃完。\n\n## 写给自己\n\n有哪件事我已经尽了力？有没有一个很小的下一步，仍然由我决定？", "source": "AI 生成"},
  {"id": "name-the-feeling", "category": "心理学", "theme": "情绪", "title": "给感觉", "subtitle": "起个名字", "excerpt": "一句更具体的话，可能让你更容易听懂自己。", "minutes": 3, "markdown": "## 写给自己\n\n今天我最容易用哪个词带过自己的感受？如果再具体一点，我会怎么写？", "source": "AI 生成"},
  {"id": "small-good-life", "category": "哲学", "theme": "生活", "title": "好的生活", "subtitle": "藏在细节里", "excerpt": "想过什么样的生活，也可以从今天的一小时看起。", "minutes": 4, "markdown": "## 写给自己\n\n如果回看这个星期，我希望在哪个具体瞬间认出自己？", "source": "AI 生成"},
  {"id": "kind-to-yourself", "category": "心理学", "theme": "善待", "title": "对自己", "subtitle": "温和一点", "excerpt": "犯错之后，你也可以用支持朋友的方式和自己说话。", "minutes": 3, "markdown": "## 写给自己\n\n如果一个亲近的人经历了同样的事，我此刻最想对他说什么？", "source": "AI 生成"}
]
"""#

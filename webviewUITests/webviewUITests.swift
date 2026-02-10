//
//  webviewUITests.swift
//  webviewUITests
//
//  Created by 차순혁 on 1/25/26.
//

import XCTest

@MainActor final class webviewUITests: XCTestCase {

    var app: XCUIApplication!
    var webView: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "WebView가 로딩되지 않음")
        let title = webView.staticTexts["Native Bridge Sample"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "index.html이 로딩되지 않음")
    }

    // MARK: - Helper

    /// WebView 내 버튼을 label로 찾아서 탭
    ///
    /// CSS overflow-y: auto 컨테이너 내 요소는 isHittable이 true여도
    /// 실제 CSS 클리핑으로 화면에 보이지 않을 수 있다.
    /// swipeUp으로 CSS 스크롤을 실행하고 frame 위치 기반으로 노출을 확인한다.
    /// (좌표 기반 press-drag는 CSS overflow에 무효하므로 swipeUp 사용)
    private func tapWebButton(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = webView.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "버튼을 찾지 못함: \(label)", file: file, line: line)

        // 로그 패널이 하단 33vh를 차지하므로, 하단 35% 이내는 CSS 클리핑 영역
        let safeMaxY = webView.frame.maxY - webView.frame.height * 0.35

        for _ in 0..<5 {
            if button.frame.midY < safeMaxY { break }
            webView.swipeUp(velocity: .slow)
            usleep(500_000)
        }

        usleep(300_000)
        button.tap()
    }

    /// WebView 로그 영역에 특정 텍스트가 나타날 때까지 대기
    private func waitForLogText(containing text: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let element = webView.staticTexts.containing(predicate).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "로그에 '\(text)' 텍스트가 나타나지 않음", file: file, line: line)
    }

    /// 원래 페이지(index.html) 타이틀이 사라지는지 확인 (페이지 이탈 검증)
    private func assertPageNavigated(timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let originalTitle = webView.staticTexts["Native Bridge Sample"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: originalTitle
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "페이지 이동이 발생하지 않음", file: file, line: line)
    }

    // MARK: - 앱 실행 & WebView 로딩

    func testAppLaunch_WebView가_정상_로딩된다() throws {
        let initLog = webView.staticTexts["Bridge 초기화 완료"]
        XCTAssertTrue(initLog.waitForExistence(timeout: 5), "Bridge 초기화 로그가 없음")
    }

    // MARK: - JS → Native Bridge 통신

    func testBridge_greeting_메시지_전송_및_응답() throws {
        tapWebButton("Native에 메시지 보내기")
        waitForLogText(containing: "수신")
    }

    func testBridge_getUserInfo_응답_수신() throws {
        tapWebButton("Native에서 데이터 요청")
        waitForLogText(containing: "차순혁")
    }

    func testBridge_getAppVersion_응답_수신() throws {
        tapWebButton("앱 버전 정보 요청")
        waitForLogText(containing: "앱 버전")
    }

    func testBridge_showToast_토스트_표시() throws {
        tapWebButton("Native 토스트 표시")

        // 토스트는 네이티브 UILabel로 표시되나, WKWebView가 접근성 트리를 독점하여
        // XCUITest에서 네이티브 UILabel을 직접 감지할 수 없음
        // → Bridge 응답 로그를 통해 토스트 표시 로직이 실행되었음을 검증
        waitForLogText(containing: "토스트를 표시합니다")
    }

    func testBridge_unknownType_에러_응답() throws {
        tapWebButton("알 수 없는 Bridge 메시지 전송 (에러 테스트)")
        waitForLogText(containing: "요청을 처리할 수 없습니다")
    }

    // MARK: - Navigation 테스트

    func testNavigation_URL입력_이동() throws {
        // 기본값 https://www.apple.com 으로 이동
        tapWebButton("이동")
        assertPageNavigated()
    }

    func testNavigation_화이트리스트_미등록_도메인_차단_알럿() throws {
        tapWebButton("화이트리스트 미등록 도메인 (보안 테스트)")

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "도메인 차단 에러 알럿이 표시되지 않음")

        let errorMessage = alert.staticTexts.containing(NSPredicate(format: "label CONTAINS '허용되지 않은'"))
        XCTAssertTrue(errorMessage.firstMatch.exists, "차단 에러 메시지가 없음")

        alert.buttons["확인"].tap()
    }

    func testNavigation_존재하지않는_URL_에러_알럿() throws {
        tapWebButton("존재하지 않는 URL 로딩 (에러 테스트)")

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "DNS 실패 에러 알럿이 표시되지 않음")

        alert.buttons["확인"].tap()
    }

    func testNavigation_HTTP404_에러_알럿() throws {
        tapWebButton("HTTP 404 응답 (navigationResponse 테스트)")

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "HTTP 404 에러 알럿이 표시되지 않음")

        let errorMessage = alert.staticTexts.containing(NSPredicate(format: "label CONTAINS 'HTTP'"))
        XCTAssertTrue(errorMessage.firstMatch.exists, "HTTP 에러 메시지가 없음")

        alert.buttons["확인"].tap()
    }

    // MARK: - JS Dialog → Native Alert

    func testJSDialog_alert_네이티브_알럿으로_변환() throws {
        tapWebButton("alert() 테스트")

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "JS alert가 네이티브 알럿으로 변환되지 않음")

        let message = alert.staticTexts.containing(NSPredicate(format: "label CONTAINS 'JS alert()'"))
        XCTAssertTrue(message.firstMatch.exists, "알럿 메시지 내용이 일치하지 않음")

        alert.buttons["확인"].tap()
    }

    func testJSDialog_confirm_확인_선택() throws {
        tapWebButton("confirm() 테스트")

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "JS confirm이 네이티브 알럿으로 변환되지 않음")

        alert.buttons["확인"].tap()

        waitForLogText(containing: "true")
    }

    func testJSDialog_confirm_취소_선택() throws {
        tapWebButton("confirm() 테스트")

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))

        alert.buttons["취소"].tap()

        waitForLogText(containing: "false")
    }

    func testJSDialog_prompt_입력_및_확인() throws {
        tapWebButton("prompt() 테스트")

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "JS prompt가 네이티브 알럿으로 변환되지 않음")

        alert.buttons["확인"].tap()

        waitForLogText(containing: "차순혁")
    }

    // MARK: - 새 창/탭 테스트

    func testWindowOpen_모달_표시_및_닫기() throws {
        tapWebButton("window.open() 모달 (createWebViewWith)")

        // 팝업 VC가 모달로 표시되면 새 WebView가 나타남
        let newWebView = app.webViews.element(boundBy: 1)
        XCTAssertTrue(newWebView.waitForExistence(timeout: 10), "window.open 팝업이 표시되지 않음")

        // 닫기 버튼 (xmark SF Symbol)으로 팝업 닫기
        let closeButton = app.buttons["xmark"]
        if closeButton.waitForExistence(timeout: 5) {
            closeButton.tap()
        }
    }

    func testBridge_openUrl_네비게이션_Push() throws {
        tapWebButton("Bridge openUrl 푸시 (제스처 충돌 테스트)")
        assertPageNavigated()
    }

    // MARK: - 환경 정보

    func testUserAgent_커스텀_식별자_포함() throws {
        tapWebButton("User-Agent 확인")
        waitForLogText(containing: "webviewSample")
    }

}

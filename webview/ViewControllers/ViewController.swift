//
//  ViewController.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import UIKit
import WebKit

/// WKWebView를 표시하고 로컬 HTML을 로딩하는 ViewController
/// - Bridge 통신 로직은 BridgeHandler에 위임하여 ViewController는 화면 구성에만 집중
class ViewController: UIViewController {

    // MARK: - Properties

    /// Bridge 통신을 전담하는 핸들러 객체
    /// - ViewController가 WKScriptMessageHandler를 직접 채택하지 않고 위임
    private let bridgeHandler = BridgeHandler()

    private var webView: WKWebView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        loadLocalHTML()
    }

    /// WKWebView는 messageHandler를 strong 참조하므로, deinit 시 반드시 해제
    /// - 해제하지 않으면 ViewController가 메모리에서 해제되지 않는 retain cycle 발생
    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: BridgeHandler.handlerName)
    }

    // MARK: - Setup

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()

        /// JS에서 window.webkit.messageHandlers.nativeBridge.postMessage()로 호출할 수 있도록 등록
        /// - handlerName을 BridgeHandler.handlerName으로 참조하여 문자열 중복 제거
        configuration.userContentController.add(bridgeHandler, name: BridgeHandler.handlerName)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false

        /// WebView 생성 후 BridgeHandler에 참조를 주입
        /// - BridgeHandler가 evaluateJavaScript로 JS 콜백을 호출하기 위해 필요
        bridgeHandler.configure(webView: webView)

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Load HTML

    /// Bundle에 포함된 로컬 HTML 파일을 로딩
    /// - allowingReadAccessTo: HTML이 참조하는 JS, CSS 등 같은 디렉토리 내 리소스 접근을 허용
    private func loadLocalHTML() {
        guard let htmlURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html"
        ) else {
            print("❌ index.html 못 찾음")
            return
        }

        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }
}

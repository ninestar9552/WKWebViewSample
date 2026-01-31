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
        let configuration = createWebViewConfiguration()

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false

        /// WebView 생성 후 BridgeHandler에 참조를 주입
        /// - BridgeHandler가 evaluateJavaScript로 JS 콜백을 호출하기 위해 필요
        bridgeHandler.configure(webView: webView)

        /// 스크롤 시 키보드 자동 숨김 (입력 폼이 있는 웹뷰에서 유용)
        webView.scrollView.keyboardDismissMode = .onDrag

        /// WebView 배경색을 뷰와 동일하게 맞춤 (로딩 시 흰색 깜빡임 방지)
        webView.isOpaque = false
        webView.backgroundColor = .clear

        /// pull-to-refresh 등 over scroll 시 배경이 보이지 않도록 bounce 비활성화
        webView.scrollView.bounces = false

        /// Safari Web Inspector 디버깅 허용 (iOS 16.4+)
        /// - Safari → 개발자용 → 시뮬레이터/기기 선택으로 WebView 디버깅 가능
        /// - DEBUG 빌드에서만 활성화하여 릴리스 빌드에서는 비활성화
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Configuration

    /// WKWebViewConfiguration 생성
    /// - WebView 생성 전에 반드시 설정해야 하는 항목들을 모아서 관리
    /// - WebView 생성 후에는 configuration을 변경할 수 없으므로 별도 메서드로 분리
    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()

        // --- Bridge 등록 ---

        /// JS에서 window.webkit.messageHandlers.nativeBridge.postMessage()로 호출할 수 있도록 등록
        configuration.userContentController.add(bridgeHandler, name: BridgeHandler.handlerName)

        // --- 기본 설정 ---

        /// JavaScript 활성화 (WKWebView 기본값 true이지만 명시적으로 선언)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        /// 텍스트 상호작용 활성화 (iOS 15+, 길게 눌러 텍스트 선택/복사 등)
        if #available(iOS 15.0, *) {
            configuration.preferences.isTextInteractionEnabled = true
        }

        return configuration
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

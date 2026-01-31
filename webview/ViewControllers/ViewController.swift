//
//  ViewController.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import UIKit
import WebKit
import Combine

/// WKWebView를 표시하고 로컬 HTML을 로딩하는 ViewController
/// - Bridge 통신 로직은 BridgeHandler에 위임하여 ViewController는 화면 구성에만 집중
/// - ViewModel의 @Published 상태를 Combine으로 구독하여 UI를 업데이트
class ViewController: UIViewController {

    // MARK: - Properties

    /// Bridge 통신을 전담하는 핸들러 객체
    private let bridgeHandler = BridgeHandler()

    /// 비즈니스 로직과 상태를 관리하는 ViewModel
    private let viewModel = WebViewViewModel()

    /// Combine 구독을 저장하는 Set
    private var cancellables = Set<AnyCancellable>()

    private var webView: WKWebView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupBindings()
        loadLocalHTML()
    }

    /// WKWebView는 messageHandler를 strong 참조하므로, deinit 시 반드시 해제
    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: BridgeHandler.handlerName)
    }

    // MARK: - Setup

    private func setupWebView() {
        let configuration = createWebViewConfiguration()

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false

        /// WebView 생성 후 BridgeHandler와 ViewModel에 상호 참조를 주입
        bridgeHandler.configure(webView: webView, viewModel: viewModel)
        viewModel.configure(bridgeHandler: bridgeHandler)

        /// 스크롤 시 키보드 자동 숨김 (입력 폼이 있는 웹뷰에서 유용)
        webView.scrollView.keyboardDismissMode = .onDrag

        /// WebView 배경색을 뷰와 동일하게 맞춤 (로딩 시 흰색 깜빡임 방지)
        webView.isOpaque = false
        webView.backgroundColor = .clear

        /// pull-to-refresh 등 over scroll 시 배경이 보이지 않도록 bounce 비활성화
        webView.scrollView.bounces = false

        /// Safari Web Inspector 디버깅 허용 (iOS 16.4+)
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

    // MARK: - Combine Bindings

    /// ViewModel의 @Published 프로퍼티를 구독하여 UI 업데이트
    private func setupBindings() {
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                _ = self
                // 로딩 인디케이터 표시/숨김 처리
                print("isLoading: \(isLoading)")
            }
            .store(in: &cancellables)

        viewModel.$loadProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                _ = self
                // 프로그레스바 업데이트 처리
                print("loadProgress: \(progress)")
            }
            .store(in: &cancellables)

        viewModel.$error
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                _ = self
                // 에러 알림 표시 처리
                print("ViewModel error: \(error.localizedDescription)")
            }
            .store(in: &cancellables)

    }

    // MARK: - Configuration

    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()

        /// JS에서 window.webkit.messageHandlers.nativeBridge.postMessage()로 호출할 수 있도록 등록
        configuration.userContentController.add(bridgeHandler, name: BridgeHandler.handlerName)

        /// JavaScript 활성화
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        /// 텍스트 상호작용 활성화 (iOS 15+, 길게 눌러 텍스트 선택/복사 등)
        if #available(iOS 15.0, *) {
            configuration.preferences.isTextInteractionEnabled = true
        }

        return configuration
    }

    // MARK: - Load HTML

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

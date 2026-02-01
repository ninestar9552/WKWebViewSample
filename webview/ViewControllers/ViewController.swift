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

    /// 페이지 로딩 진행률을 표시하는 프로그레스바
    /// - WebView 상단에 위치하여 로딩 상태를 시각적으로 전달
    private let progressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.progressTintColor = .systemBlue
        pv.trackTintColor = .clear
        return pv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupProgressView()
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
        webView.navigationDelegate = self

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

    private func setupProgressView() {
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    // MARK: - Combine Bindings

    /// ViewModel의 @Published 프로퍼티를 Combine으로 구독하여 UI에 반영
    /// - KVO 퍼블리셔로 WebView의 estimatedProgress를 관찰하여 ViewModel에 전달
    /// - ViewModel → ViewController 방향의 단방향 바인딩
    private func setupBindings() {

        /// WKWebView의 estimatedProgress를 KVO 퍼블리셔로 관찰하여 ViewModel에 전달
        /// - WKWebView는 로딩 진행률을 KVO로만 제공하므로 Combine publisher(for:)로 변환
        webView.publisher(for: \.estimatedProgress)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.viewModel.updateLoadProgress(progress)
            }
            .store(in: &cancellables)

        /// 프로그레스바를 단일 sink에서 제어하여 타이밍 충돌 방지
        /// - progress 0 초과 ~ 1 미만: 프로그레스바 표시 및 값 업데이트
        /// - progress 1.0 도달: 1.0까지 채운 뒤 0.5초 후 페이드아웃
        /// - progress 0.0 (에러 시 리셋): 프로그레스바 즉시 숨김
        viewModel.$loadProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                if progress > 0 && progress < 1.0 {
                    self.progressView.isHidden = false
                    self.progressView.alpha = 1
                    self.progressView.setProgress(Float(progress), animated: true)
                } else if progress >= 1.0 {
                    self.progressView.setProgress(1.0, animated: true)
                    UIView.animate(withDuration: 0.3, delay: 0.5) {
                        self.progressView.alpha = 0
                    } completion: { _ in
                        self.progressView.isHidden = true
                        self.progressView.setProgress(0, animated: false)
                    }
                } else {
                    self.progressView.isHidden = true
                    self.progressView.setProgress(0, animated: false)
                }
            }
            .store(in: &cancellables)

        viewModel.$error
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.showErrorAlert(error)
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

    // MARK: - Error Handling

    private func showErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "오류",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - WKNavigationDelegate

/// WebView 네비게이션 이벤트 처리
/// - 로딩 상태는 KVO estimatedProgress가 단일 소스로 관리
/// - NavigationDelegate는 에러 처리만 담당
extension ViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        viewModel.handleError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        viewModel.handleError(error)
    }
}

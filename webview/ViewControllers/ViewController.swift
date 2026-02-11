//
//  ViewController.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import UIKit
import WebKit
import Combine
import ComposableArchitecture

// ============================================================================
// MARK: - MVVM vs TCA: ViewController 역할 변화
// ============================================================================
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ MVVM (기존)                                                             │
// │                                                                         │
// │ let viewModel = WebViewViewModel()     ← ViewModel 직접 생성            │
// │ viewModel.$loadProgress.sink { }       ← Combine으로 상태 구독          │
// │ viewModel.handleError(error)           ← 메서드 직접 호출               │
// │ viewModel.configure(bridgeHandler:)    ← 양방향 의존성 수동 연결         │
// ├─────────────────────────────────────────────────────────────────────────┤
// │ TCA (변환 후)                                                           │
// │                                                                         │
// │ let store: StoreOf<WebViewFeature>     ← Store 생성 (Reducer + State)   │
// │ store.publisher.loadProgress.sink { }  ← 동일한 Combine 패턴            │
// │ store.send(.errorOccurred(message))    ← 액션을 "보냄"                  │
// │ bridgeClient = BridgeClient(...)       ← Dependency로 주입              │
// └─────────────────────────────────────────────────────────────────────────┘

/// WKWebView를 표시하고 로컬 HTML을 로딩하는 ViewController
/// - Bridge 통신 로직은 BridgeHandler에 위임하여 ViewController는 화면 구성에만 집중
/// - MVVM: ViewModel의 @Published 상태를 Combine으로 구독
/// - TCA: Store의 publisher를 Combine으로 구독 (동일한 패턴)
/// - 팝업 모드: createWebViewWith에서 전달받은 configuration으로 생성되어 새 창으로 표시
final class ViewController: UIViewController {

    // MARK: - Properties

    /// Bridge 통신을 전담하는 핸들러 객체
    private let bridgeHandler = BridgeHandler()

    /// TCA Store — 비즈니스 로직과 상태를 관리
    /// - MVVM: let viewModel = WebViewViewModel()
    /// - TCA: Store<WebViewFeature.State, WebViewFeature.Action>
    ///
    /// lazy 이유: BridgeClient에 bridgeHandler.sendRawJS를 연결해야 하므로
    /// bridgeHandler가 먼저 초기화된 후 Store를 생성
    private(set) lazy var store: StoreOf<WebViewFeature> = {
        /// bridgeHandler를 로컬 변수로 캡처하여 @Sendable 클로저에서 사용
        /// - [weak self]로 캡처하면 "reference to captured var 'self'" 에러 발생
        /// - class 타입이므로 weak 캡처 가능
        let handler = self.bridgeHandler
        return Store(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            /// BridgeClient의 실제 구현을 BridgeHandler에 연결
            /// - MVVM: viewModel.configure(bridgeHandler: bridgeHandler)
            /// - TCA: Dependency로 주입 — sendRawJS 클로저가 bridgeHandler를 캡처
            ///
            /// Task { @MainActor in } 이유:
            /// - BridgeHandler.sendRawJS는 MainActor에 격리됨 (WKScriptMessageHandler 채택)
            /// - BridgeClient.sendRawJS는 @Sendable 클로저 (Effect.run의 nonisolated 컨텍스트에서 호출)
            /// - nonisolated → MainActor 호출이므로 Task로 디스패치 필요
            $0.bridgeClient = BridgeClient(sendRawJS: { [weak handler] function, jsonString in
                Task { @MainActor in
                    handler?.sendRawJS(function: function, jsonString: jsonString)
                }
            })
        }
    }()

    /// Combine 구독 저장소
    /// - MVVM/TCA 모두 Combine .sink를 사용하므로 그대로 유지
    var cancellables = Set<AnyCancellable>()

    /// WebView 인스턴스 (createWebViewWith에서 반환해야 하므로 internal 접근)
    private(set) var webView: WKWebView!

    /// 외부에서 주입받은 configuration (팝업 모드 - window.open)
    private var externalConfiguration: WKWebViewConfiguration?

    /// 외부에서 주입받은 URL (푸시 모드 - Bridge openUrl)
    private var initialURL: URL?

    /// 백화현상 복구용 마지막 유효 URL
    var lastLoadedURL: URL?

    /// 백화현상 발생 여부 (didBecomeActive에서 복구)
    var needsReload = false

    /// 팝업 모드 여부 (window.open → 모달)
    private var isPopupMode: Bool { externalConfiguration != nil }

    // MARK: - UI Components

    let progressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.progressTintColor = .systemBlue
        pv.trackTintColor = .clear
        return pv
    }()

    private lazy var navigationBar: PopupNavigationBar = {
        let bar = PopupNavigationBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.onClose = { [weak self] in
            self?.dismiss(animated: true)
        }
        return bar
    }()

    // MARK: - Initialization

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// 팝업 모드 생성자 (window.open → 모달)
    convenience init(configuration: WKWebViewConfiguration) {
        self.init(nibName: nil, bundle: nil)
        self.externalConfiguration = configuration
    }

    /// 푸시 모드 생성자 (Bridge openUrl → 네비게이션 push)
    convenience init(url: URL) {
        self.init(nibName: nil, bundle: nil)
        self.initialURL = url
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        if isPopupMode {
            setupNavigationBar()
        }

        setupWebView()
        setupProgressView()
        setupBindings()

        loadInitialContent()
    }

    /// 모드에 따라 초기 콘텐츠 로드
    private func loadInitialContent() {
        if let url = initialURL {
            // 푸시 모드: 외부 URL 로드
            webView.load(URLRequest(url: url))
        } else if !isPopupMode {
            // 일반 모드: 로컬 HTML 로드
            loadLocalHTML()
        }
        // 팝업 모드: WebKit이 자동으로 페이지 로드
    }

    deinit {
        /// deinit은 nonisolated이지만 실제로는 메인 스레드에서 호출됨
        /// assumeIsolated로 MainActor 프로퍼티 접근을 허용
        MainActor.assumeIsolated {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: BridgeHandler.handlerName)
        }
    }

    // MARK: - Setup UI

    private func setupNavigationBar() {
        view.addSubview(navigationBar)

        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBar.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupWebView() {
        let configuration = createWebViewConfiguration()

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self

        configureUserAgent()
        configureWebViewAppearance()
        configureDependencies()

        view.addSubview(webView)

        /// 팝업 모드: 네비게이션 바 아래에 프로그레스바 배치
        /// 일반 모드: Safe Area 상단에 프로그레스바 배치
        let topAnchor = isPopupMode
            ? navigationBar.bottomAnchor
            : view.safeAreaLayoutGuide.topAnchor

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupProgressView() {
        view.addSubview(progressView)

        let topAnchor = isPopupMode
            ? navigationBar.bottomAnchor
            : view.safeAreaLayoutGuide.topAnchor

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    // MARK: - WebView Configuration

    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = externalConfiguration ?? WKWebViewConfiguration()

        /// 팝업 모드: userContentController만 새로 생성하여 독립성 확보
        if externalConfiguration != nil {
            configuration.userContentController = WKUserContentController()
        }

        configuration.userContentController.add(bridgeHandler, name: BridgeHandler.handlerName)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        /// 텍스트 상호작용 활성화 (iOS 15+, 길게 눌러 텍스트 선택/복사 등)
        if #available(iOS 15.0, *) {
            configuration.preferences.isTextInteractionEnabled = true
        }

        return configuration
    }

    /// Custom User-Agent 설정
    private func configureUserAgent() {
        let device = UIDevice.current
        let customAgent = "webviewSample/\(Bundle.main.appVersion) iOS/\(device.systemVersion) \(device.modelIdentifier)"

        webView.customUserAgent = nil
        Task { [weak self] in
            guard let self else { return }
            if let defaultAgent = try? await webView.evaluateJavaScript("navigator.userAgent") as? String {
                webView.customUserAgent = "\(defaultAgent) \(customAgent)"
            }
        }
    }

    private func configureWebViewAppearance() {
        webView.scrollView.keyboardDismissMode = .onDrag
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = true

        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
    }

    /// 의존성 연결
    /// - MVVM: bridgeHandler ↔ viewModel 양방향 참조 설정
    /// - TCA: bridgeHandler에 WebView만 주입 + onMessageReceived로 Store 연결
    ///   (BridgeClient → bridgeHandler 연결은 Store 생성 시 withDependencies에서 처리)
    private func configureDependencies() {
        bridgeHandler.configure(webView: webView)

        /// BridgeHandler가 메시지를 수신하면 Store에 액션으로 전달
        /// - MVVM: bridgeHandler → viewModel.handleBridgeMessage(request)
        /// - TCA: bridgeHandler → store.send(.bridgeMessageReceived(request))
        bridgeHandler.onMessageReceived = { [weak self] request in
            self?.store.send(.bridgeMessageReceived(request))
        }
    }

    // MARK: - Load HTML

    private func loadLocalHTML() {
        guard let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            print("❌ index.html 못 찾음")
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

}

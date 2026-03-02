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
// │ TCA — store.publisher (이 프로젝트에서 사용하는 방식)                     │
// │                                                                         │
// │ let store: StoreOf<WebViewFeature>     ← Store 생성 (Reducer + State)   │
// │ store.publisher.loadProgress.sink { }  ← Combine으로 상태 구독          │
// │ store.send(.errorOccurred(message))    ← 액션을 "보냄"                  │
// │ var cancellables = Set<AnyCancellable> ← 모든 구독 저장                 │
// │ import Combine                         ← 필수                           │
// ├─────────────────────────────────────────────────────────────────────────┤
// │ TCA — observe { } (@ObservableState 매크로 사용 시)                      │
// │                                                                         │
// │ let store: StoreOf<WebViewFeature>     ← Store 생성 (동일)              │
// │ observe { store.loadProgress }         ← 상태별 observe 블록으로 구독   │
// │ observe { store.errorMessage }         ← 해당 상태 변경 시에만 재실행   │
// │ store.send(.errorOccurred(message))    ← 액션을 "보냄" (동일)           │
// │ var cancellables = Set<AnyCancellable> ← KVO/Notification 전용으로 축소 │
// │ import Combine                         ← KVO/Notification 있으면 유지   │
// │                                                                         │
// │ 차이점:                                                                  │
// │ - store.publisher.xxx.sink → observe { store.xxx } (상태별 분리 유지)   │
// │ - store.xxx 로 직접 상태 접근 (publisher 경유 X)                         │
// │ - Combine 보일러플레이트 제거 (.sink/.receive/.compactMap/cancellables)  │
// │ - cancellables 역할 축소 (Store 구독 제거, KVO/Notification만 남음)      │
// │ - Combine import는 KVO/Notification 때문에 여전히 필요                   │
// └─────────────────────────────────────────────────────────────────────────┘

/// WKWebView를 표시하고 로컬 HTML을 로딩하는 ViewController
/// - Bridge 통신 로직은 BridgeHandler에 위임하여 ViewController는 화면 구성에만 집중
/// - MVVM: ViewModel의 @Published 상태를 Combine으로 구독
/// - TCA (store.publisher): Store의 publisher를 Combine으로 구독 (동일한 패턴)
/// - TCA (@ObservableState): observe { } 블록에서 store.xxx로 직접 접근 (Combine 불필요)
/// - 팝업 모드: createWebViewWith에서 전달받은 configuration으로 생성되어 새 창으로 표시
final class ViewController: UIViewController {

    // MARK: - Properties

    /// Bridge 통신을 전담하는 핸들러 객체
    private let bridgeHandler = BridgeHandler()

    /// TCA Store — 비즈니스 로직과 상태를 관리
    /// - MVVM: let viewModel = WebViewViewModel()
    /// - TCA: Store<WebViewFeature.State, WebViewFeature.Action>
    ///
    /// @ObservableState 사용 시:
    /// - Store 생성 방식은 동일 (withDependencies 포함)
    /// - 상태 접근 방식만 변경: store.publisher.xxx → store.xxx (observe 블록 내)
    /// - store.send(.action) 호출 방식은 동일
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
            /// - @ObservableState: 동일 — 의존성 주입 방식은 변하지 않음
            ///
            /// Task { @MainActor in } 이유:
            /// - BridgeHandler.sendRawJS는 MainActor에 격리됨 (WKScriptMessageHandler 채택)
            /// - BridgeClient.sendRawJS는 @Sendable 클로저 (Effect.run의 nonisolated 컨텍스트에서 호출)
            /// - nonisolated → MainActor 호출이므로 Task로 디스패치 필요
            $0.bridgeClient = BridgeClient(sendRawJS: { [weak handler] jsonData in
                Task { @MainActor in
                    await handler?.sendRawJS(jsonData: jsonData)
                }
            })
        }
    }()

    /// Combine 구독 저장소
    /// - MVVM/TCA(store.publisher): 모든 상태 구독 + KVO/Notification 저장
    /// - TCA(@ObservableState): Store 상태 구독은 observe { }가 대체하므로
    ///   KVO(estimatedProgress)와 NotificationCenter(didBecomeActive) 전용으로 축소
    ///   → Store 구독 5개 제거, KVO 1개 + Notification 1개만 남음
    var cancellables = Set<AnyCancellable>()

    /// WebView 인스턴스 (createWebViewWith에서 반환해야 하므로 internal 접근)
    private(set) var webView: WKWebView!

    /// 외부에서 주입받은 configuration (팝업 모드 - window.open)
    private var externalConfiguration: WKWebViewConfiguration?

    /// 외부에서 주입받은 URL (푸시 모드 - Bridge openUrl)
    private var initialURL: URL?

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
    /// - @ObservableState: 동일 — store.send(.action) 호출 방식은 변하지 않음
    private func configureDependencies() {
        bridgeHandler.configure(webView: webView)

        /// BridgeHandler가 메시지를 수신하면 Store에 액션으로 전달
        /// - MVVM: bridgeHandler → viewModel.handleBridgeMessage(request)
        /// - TCA: bridgeHandler → store.send(.bridgeMessageReceived(request))
        /// - @ObservableState: 동일 — store.send()는 구독 방식과 무관
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

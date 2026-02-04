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
/// - 팝업 모드: createWebViewWith에서 전달받은 configuration으로 생성되어 새 창으로 표시
final class ViewController: UIViewController {

    // MARK: - Properties

    /// Bridge 통신을 전담하는 핸들러 객체
    private let bridgeHandler = BridgeHandler()

    /// 비즈니스 로직과 상태를 관리하는 ViewModel
    /// - Delegate extension 파일에서 viewModel.handleError() 접근을 위해 internal
    let viewModel = WebViewViewModel()
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
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: BridgeHandler.handlerName)
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
    /// - 기본 User-Agent 뒤에 앱 정보를 추가하여 서버/웹에서 앱 환경을 식별할 수 있도록 함
    /// - 웹 프론트엔드에서 navigator.userAgent로 네이티브 앱 여부를 판별하여 Bridge 호출 분기에 사용
    private func configureUserAgent() {
        let device = UIDevice.current
        let customAgent = "webviewSample/\(Bundle.main.appVersion) iOS/\(device.systemVersion) \(device.modelIdentifier)"

        webView.customUserAgent = nil
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
            if let defaultAgent = result as? String {
                self?.webView.customUserAgent = "\(defaultAgent) \(customAgent)"
            }
        }
    }

    private func configureWebViewAppearance() {
        /// 스크롤 시 키보드 자동 숨김 (입력 폼이 있는 웹뷰에서 유용)
        webView.scrollView.keyboardDismissMode = .onDrag
        /// WebView 배경색을 뷰와 동일하게 맞춤 (로딩 시 흰색 깜빡임 방지)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        /// pull-to-refresh 등 over scroll 시 배경이 보이지 않도록 bounce 비활성화
        webView.scrollView.bounces = false

        /// 스와이프로 웹 히스토리 앞/뒤 이동 허용
        /// - WebView에 히스토리가 없으면 자동으로 Navigation pop 제스처가 작동
        webView.allowsBackForwardNavigationGestures = true

        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
    }

    private func configureDependencies() {
        bridgeHandler.configure(webView: webView, viewModel: viewModel)
        viewModel.configure(bridgeHandler: bridgeHandler)
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

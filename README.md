# iOS WebView Bridge Sample

WKWebView 기반의 하이브리드 앱 아키텍처 샘플 프로젝트입니다.
**MVVM + Combine** 패턴을 적용하여 Native ↔ JavaScript 간 양방향 통신을 구현했습니다.

## 주요 기능

| 기능 | 설명 |
|------|------|
| **Bridge 통신** | JS ↔ Native 양방향 메시지 전달 (postMessage / evaluateJavaScript) |
| **MVVM + Combine** | ViewModel의 @Published 상태를 Combine으로 UI에 바인딩 |
| **도메인 화이트리스트** | 허용된 도메인만 로딩, 미등록 도메인 차단 |
| **window.open 처리** | 새 창 요청 시 모달로 ViewController 표시 |
| **백화현상 복구** | WebContent 프로세스 종료 시 자동 복구 |
| **프로그레스바** | KVO estimatedProgress를 Combine으로 바인딩 |
| **JS Dialog** | alert, confirm, prompt를 Native UIAlertController로 변환 |

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                          WKWebView                              │
│                        (JavaScript)                             │
└──────────────────────────┬──────────────────────────────────────┘
                           │ postMessage
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                       BridgeHandler                             │
│              • WKScriptMessageHandler 구현                       │
│              • 메시지 파싱 및 라우팅                                 │
│              • sendToJS()로 응답 전송                              │
└──────────────────────────┬──────────────────────────────────────┘
                           │ viewModel.handleBridgeMessage()
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                     WebViewViewModel                            │
│              • @Published: loadProgress, error                  │
│              • @Event: urlToOpen, toastMessage                  │
│              • 비즈니스 로직 처리                                   │
└──────────────────────────┬──────────────────────────────────────┘
                           │ Combine ($published)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ViewController                             │
│              • setupBindings()로 상태 구독                         │
│              • UI 업데이트 (프로그레스바, 토스트, 알럿)                  │
│              • WKNavigationDelegate, WKUIDelegate               │
└─────────────────────────────────────────────────────────────────┘
```

## 프로젝트 구조

```
webview/
├── App/
│   ├── AppDelegate.swift
│   └── SceneDelegate.swift
│
├── Bridge/
│   ├── BridgeHandler.swift        # WKScriptMessageHandler 구현
│   ├── BridgeMessageType.swift    # 메시지 타입 enum
│   ├── BridgeRequest.swift        # JS → Native 요청 모델
│   ├── BridgeResponse.swift       # Native → JS 응답 모델
│   └── AnyCodable.swift           # 동적 JSON 디코딩 유틸
│
├── ViewModels/
│   └── WebViewViewModel.swift     # 비즈니스 로직 + 상태 관리
│
├── ViewControllers/
│   ├── ViewController.swift                    # 메인 WebView 화면
│   ├── ViewController+Bindings.swift           # Combine 바인딩
│   ├── ViewController+WKNavigationDelegate.swift
│   └── ViewController+WKUIDelegate.swift
│
├── Views/
│   └── PopupNavigationBar.swift   # window.open 팝업용 네비게이션 바
│
├── Config/
│   └── SecurityConfig.swift       # 도메인 화이트리스트 설정
│
├── Utils/
│   └── Event.swift                # @Event 프로퍼티 래퍼 (일회성 이벤트)
│
├── Extensions/
│   ├── Bundle+AppInfo.swift       # 앱 버전 정보
│   └── UIDevice+Model.swift       # 디바이스 모델명
│
└── Resources/
    ├── index.html                 # 테스트용 웹 페이지
    └── bridge.js                  # JS Bridge 모듈
```

## 데이터 흐름

### JS → Native 요청

```
[JS] postToNative({ type: "showToast", data: { message: "Hello" } })
         │
         ▼
[BridgeHandler] userContentController(didReceive:)
         │ JSONDecoder → BridgeRequest
         ▼
[ViewModel] handleBridgeMessage() → handleShowToast()
         │ toastMessage = "Hello"  (@Event)
         ▼
[ViewController] bindToast() sink → showToast() UI 표시
```

### Native → JS 응답

```
[ViewModel] bridgeHandler.sendToJS(function: "callback", response: ...)
         │
         ▼
[BridgeHandler] webView.evaluateJavaScript("callback({...})")
         │
         ▼
[JS] function callback(response) { ... }
```

## Bridge 메시지 규격

### 요청 (JS → Native)

```javascript
{
  "type": "showToast",           // BridgeMessageType
  "callback": "onToastResult",   // 응답받을 JS 함수명
  "data": {                      // 요청 데이터
    "message": "저장되었습니다"
  }
}
```

### 응답 (Native → JS)

```javascript
{
  "success": true,               // 처리 성공 여부
  "message": "토스트를 표시합니다",  // 안내 메시지
  "data": { ... }                // 응답 데이터 (선택)
}
```

## 지원 Bridge 타입

| Type | 설명 | 요청 데이터 | 응답 데이터 |
|------|------|------------|------------|
| `greeting` | 인사 메시지 에코 | `{ text }` | `{ text }` |
| `getUserInfo` | 사용자/디바이스 정보 | - | `{ name, device, osVersion }` |
| `getAppVersion` | 앱 버전 정보 | - | `{ appVersion, osVersion, device }` |
| `openUrl` | 새 화면에서 URL 열기 | `{ url }` | - |
| `showToast` | 토스트 메시지 표시 | `{ message }` | - |

## 기술 스택

- **iOS 15.0+**
- **Swift 6**
- **WKWebView** (WebKit)
- **Combine** (Reactive 바인딩)
- **MVVM** 아키텍처

## 주요 구현 포인트

### @Event 프로퍼티 래퍼

일회성 이벤트를 위한 커스텀 프로퍼티 래퍼입니다.
`@Published`와 동일한 문법으로 `PassthroughSubject`를 사용합니다.

```swift
// 정의
@Event var toastMessage: String

// 이벤트 발행 (write-only)
toastMessage = "Hello"

// 구독
viewModel.$toastMessage
    .sink { message in ... }
```

### 백화현상 복구

WKWebView의 WebContent 프로세스가 메모리 부족으로 종료되면 흰 화면이 됩니다.
`didBecomeActiveNotification`을 구독하여 앱 복귀 시 자동으로 마지막 URL을 재로딩합니다.

```swift
// 프로세스 종료 감지
func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    needsReload = true
}

// 앱 활성화 시 복구
NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
    .sink { [weak self] _ in
        if self?.needsReload == true {
            self?.webView.load(URLRequest(url: lastLoadedURL))
        }
    }
```

### 도메인 화이트리스트

`SecurityConfig`에 등록된 도메인만 로딩을 허용합니다.

```swift
// Config/SecurityConfig.swift
static let allowedDomains: [String] = [
    "apple.com",
    "google.com"
]
```

# iOS WebView Bridge Sample

WKWebView 기반의 하이브리드 앱 아키텍처 샘플 프로젝트입니다.
**TCA (The Composable Architecture)** 패턴을 적용하여 Native ↔ JavaScript 간 양방향 통신을 구현했습니다.

> 원래 MVVM + Combine으로 구현된 프로젝트를 TCA로 변환하였으며,
> 코드 내 주석에 MVVM 대비 TCA에서 무엇이 달라졌는지 상세히 비교해 두었습니다.

## 주요 기능

| 기능 | 설명 |
|------|------|
| **Bridge 통신** | JS ↔ Native 양방향 메시지 전달 (postMessage / evaluateJavaScript) |
| **TCA** | Reducer로 상태 관리, Effect로 사이드 이펙트 분리, Dependency로 의존성 주입 |
| **도메인 화이트리스트** | 허용된 도메인만 로딩, 미등록 도메인 차단 |
| **window.open 처리** | 새 창 요청 시 모달로 ViewController 표시 |
| **백화현상 복구** | WebContent 프로세스 종료 시 자동 복구 |
| **프로그레스바** | KVO estimatedProgress를 Store publisher로 바인딩 |
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
│              • 메시지 파싱 (JSON → BridgeRequest)                  │
│              • sendRawJS()로 응답 전송                             │
└──────────────────────────┬──────────────────────────────────────┘
                           │ onMessageReceived?(request)
                           │ → store.send(.bridgeMessageReceived)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                   WebViewFeature (Reducer)                       │
│              • State: loadProgress, errorMessage,               │
│                       urlToOpen, toastMessage                   │
│              • Action → State 변경 + Effect 반환                  │
│              • BridgeClient Dependency로 JS 응답 전송             │
└──────────────────────────┬──────────────────────────────────────┘
                           │ store.publisher (Combine)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ViewController                             │
│              • setupBindings()로 Store 상태 구독                   │
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
├── Features/
│   └── WebViewFeature.swift       # TCA Reducer (상태 + 액션 + 로직)
│
├── Dependencies/
│   └── BridgeClient.swift         # TCA Dependency (JS 응답 전송)
│
├── ViewControllers/
│   ├── ViewController.swift                    # 메인 WebView 화면
│   ├── ViewController+Bindings.swift           # Store ↔ UI 바인딩
│   ├── ViewController+WKNavigationDelegate.swift
│   └── ViewController+WKUIDelegate.swift
│
├── Views/
│   └── PopupNavigationBar.swift   # window.open 팝업용 네비게이션 바
│
├── Config/
│   └── SecurityConfig.swift       # 도메인 화이트리스트 설정
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
[BridgeHandler] onMessageReceived?(request)
         │
         ▼
[Store] .bridgeMessageReceived(request) → Reducer에서 처리
         │ state.toastMessage = "Hello"
         ▼
[ViewController] store.publisher.toastMessage.sink → showToast() UI 표시
         │
         ▼
[ViewController] store.send(.toastShown) → state.toastMessage = nil
```

### Native → JS 응답

```
[Reducer] return .run { bridgeClient.send(function: "callback", response: ...) }
         │
         ▼
[BridgeClient] sendRawJS(function, jsonString)  ← Dependency 클로저
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

- **iOS 16.0+**
- **Swift 6** (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor)
- **WKWebView** (WebKit)
- **TCA** (The Composable Architecture)
- **Combine** (Store publisher 바인딩)

## 주요 구현 포인트

### TCA + Swift 6 actor isolation

이 프로젝트는 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 설정을 사용합니다.
TCA의 `@Reducer`, `@DependencyClient` 매크로가 생성하는 코드가 MainActor에 묶여
`Effect.run`(nonisolated 컨텍스트)과 충돌하므로, 매크로 없이 수동 구현합니다.

```swift
// 매크로 대신 nonisolated + Reducer 프로토콜 직접 채택
nonisolated struct WebViewFeature: Reducer { ... }
nonisolated struct BridgeClient: Sendable { ... }
```

### 일회성 이벤트 처리 (MVVM @Event → TCA Optional State)

MVVM의 `@Event`(PassthroughSubject)는 한 번 전달 후 자동 소비됩니다.
TCA에서는 Optional State로 유지하고, UI 처리 후 소비 Action을 보내 nil로 초기화합니다.

```swift
// State
var toastMessage: String? = nil

// Reducer: 이벤트 발생
state.toastMessage = "저장되었습니다"

// ViewController: UI 처리 후 소비
store.publisher.toastMessage
    .compactMap { $0 }
    .sink { [weak self] message in
        self?.showToast(message)
        self?.store.send(.toastShown)  // → state.toastMessage = nil
    }
```

### WKWebView Bridge Retain Cycle 방지

`userContentController.add(handler:)`가 handler를 strong 참조하므로,
ViewController가 아닌 별도 BridgeHandler 객체를 등록하여 순환 참조를 차단합니다.

```swift
// ViewController → webView → userContentController → bridgeHandler (별도 객체)
// bridgeHandler → ViewController: [weak self]로 참조 → 순환 없음
bridgeHandler.onMessageReceived = { [weak self] request in
    self?.store.send(.bridgeMessageReceived(request))
}

// deinit에서 명시적 제거
deinit {
    MainActor.assumeIsolated {
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: BridgeHandler.handlerName)
    }
}
```

### 백화현상 복구

WKWebView의 WebContent 프로세스가 메모리 부족으로 종료되면 흰 화면이 됩니다.
`didBecomeActiveNotification`을 구독하여 앱 복귀 시 자동으로 마지막 URL을 재로딩합니다.

```swift
func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    needsReload = true
}

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

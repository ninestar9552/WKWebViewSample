//
//  BridgeHandler.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import UIKit
import WebKit

// ============================================================================
// MARK: - MVVM vs TCA: BridgeHandler 역할 변화
// ============================================================================
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ MVVM (기존)                                                             │
// │                                                                         │
// │ BridgeHandler → viewModel.handleBridgeMessage(request)                  │
// │ ViewModel → bridgeHandler.sendToJS(function:response:)                  │
// │                                                                         │
// │ - BridgeMessageSender 프로토콜로 ViewModel이 BridgeHandler에 의존       │
// │ - ViewModel이 직접 sendToJS 호출 (사이드 이펙트가 ViewModel 안에 있음)   │
// ├─────────────────────────────────────────────────────────────────────────┤
// │ TCA (변환 후)                                                           │
// │                                                                         │
// │ BridgeHandler → onMessageReceived?(request)                             │
// │                  → store.send(.bridgeMessageReceived(request))          │
// │ Reducer → Effect.run { bridgeClient.send(...) }                        │
// │                  → bridgeHandler.sendRawJS(function:jsonString:)        │
// │                                                                         │
// │ - BridgeMessageSender 프로토콜 삭제 → BridgeClient Dependency로 대체    │
// │ - viewModel 참조 삭제 → 클로저 콜백(onMessageReceived)으로 대체          │
// │ - sendToJS<T> 제네릭 메서드 → sendRawJS(이미 인코딩된 JSON 전송)로 단순화│
// └─────────────────────────────────────────────────────────────────────────┘

/// JS ↔ Native 양방향 Bridge 통신을 전담하는 핸들러 (인프라 역할)
/// - 메시지 파싱(Codable 디코딩)과 JS 응답 전송만 담당
/// - MVVM: 비즈니스 로직을 viewModel.handleBridgeMessage()에 위임
/// - TCA: onMessageReceived 콜백으로 Store에 액션 전달
final class BridgeHandler: NSObject, WKScriptMessageHandler {

    /// JS에서 postMessage 호출 시 사용하는 핸들러 이름
    /// - deinit(nonisolated)에서 접근하므로 nonisolated 필수
    nonisolated static let handlerName = "nativeBridge"

    /// evaluateJavaScript 호출을 위해 WebView 참조를 보유
    private weak var webView: WKWebView?

    /// Bridge 메시지 수신 시 호출되는 콜백
    /// - MVVM: weak var viewModel: WebViewViewModel? → viewModel?.handleBridgeMessage(request)
    /// - TCA: 클로저 콜백 → store.send(.bridgeMessageReceived(request))
    var onMessageReceived: ((BridgeRequest) -> Void)?

    private let decoder = JSONDecoder()

    /// WebView 참조를 주입받는 메서드
    /// - MVVM: configure(webView:viewModel:) — WebView + ViewModel 둘 다 주입
    /// - TCA: configure(webView:) — WebView만 주입 (Store 연결은 onMessageReceived 콜백으로)
    func configure(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - WKScriptMessageHandler

    /// JS에서 window.webkit.messageHandlers.nativeBridge.postMessage() 호출 시 실행
    /// - JSON → BridgeRequest Codable 디코딩으로 타입 안전성 확보
    /// - MVVM: viewModel?.handleBridgeMessage(request)
    /// - TCA: onMessageReceived?(request) → store.send(.bridgeMessageReceived(request))
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName else { return }

        /// Bridge 메시지의 출처를 검증하여 신뢰할 수 없는 페이지의 호출을 차단
        guard SecurityConfig.isTrustedBridgeOrigin(message.frameInfo.request.url) else {
            print("[Security] 신뢰할 수 없는 출처의 Bridge 호출 차단: \(message.frameInfo.request.url?.absoluteString ?? "unknown")")
            return
        }

        print("📩 [JS → Native]\n\(message.body)")

        guard let request = decodeBridgeRequest(from: message.body) else {
            print("❌ 메시지 파싱 실패: \(message.body)")
            /// 알 수 없는 type이면 디코딩 자체가 실패하므로, callback을 수동으로 꺼내 에러 응답
            let callback = (message.body as? [String: Any])?["callback"] as? String
            sendRawJS(function: callback, jsonString: "{\"success\":false,\"message\":\"요청을 처리할 수 없습니다.\"}")
            return
        }

        onMessageReceived?(request)
    }

    // MARK: - Native → JS 응답

    /// 이미 JSON 인코딩된 문자열을 JS 콜백 함수에 전달
    /// - MVVM: sendToJS<T>(function:response:) — 제네릭으로 여기서 인코딩
    /// - TCA: sendRawJS(function:jsonString:) — BridgeClient가 이미 인코딩한 JSON을 전달받음
    ///   → BridgeClient.send()가 인코딩을 담당하므로 여기서는 전달만
    /// - callback 함수명의 유효성을 검증하여 JS Injection을 방지
    func sendRawJS(function: String?, jsonString: String) {
        guard let function = function else { return }

        guard isValidJSFunctionName(function) else {
            print("[Security] 유효하지 않은 콜백 함수명 차단: \(function)")
            return
        }

        let jsCode = "\(function)(\(jsonString));"
        print("📤 [Native → JS]\n\(jsCode)")
        webView?.evaluateJavaScript(jsCode) { @Sendable _, error in
            if let error = error {
                print("❌ JS 실행 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    /// JS 콜백 함수명의 유효성 검증 (JS Injection 방지)
    nonisolated func isValidJSFunctionName(_ name: String) -> Bool {
        let pattern = "^[a-zA-Z_$][a-zA-Z0-9_$.]*$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// postMessage의 body를 BridgeRequest로 디코딩
    private func decodeBridgeRequest(from body: Any) -> BridgeRequest? {
        guard let dict = body as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        return try? decoder.decode(BridgeRequest.self, from: jsonData)
    }
}

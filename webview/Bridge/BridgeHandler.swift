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
// │                  → bridgeHandler.sendRawJS(jsonString:)                │
// │                                                                         │
// │ - BridgeMessageSender 프로토콜 삭제 → BridgeClient Dependency로 대체    │
// │ - viewModel 참조 삭제 → 클로저 콜백(onMessageReceived)으로 대체          │
// │ - sendToJS<T> 제네릭 메서드 → sendRawJS(jsonString:)로 단순화           │
// └─────────────────────────────────────────────────────────────────────────┘

/// JS ↔ Native 양방향 Bridge 통신을 전담하는 핸들러 (인프라 역할)
/// - 메시지 파싱(Codable 디코딩)과 JS 응답 전송만 담당
/// - MVVM: 비즈니스 로직을 viewModel.handleBridgeMessage()에 위임
/// - TCA: onMessageReceived 콜백으로 Store에 액션 전달
final class BridgeHandler: NSObject, WKScriptMessageHandler {

    /// JS에서 postMessage 호출 시 사용하는 핸들러 이름
    /// - deinit(nonisolated)에서 접근하므로 nonisolated 필수
    nonisolated static let handlerName = "nativeBridge"

    /// callAsyncJavaScript 호출을 위해 WebView 참조를 보유
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
            /// 알 수 없는 method이면 디코딩 자체가 실패하므로, id를 수동으로 꺼내 에러 응답
            /// userContentController는 sync이므로 Task로 감싸서 async sendRawJS 호출
            let id = (message.body as? [String: Any])?["id"] as? String ?? "unknown"
            let errorResponse: [String: Any] = [
                "id": id,
                "error": ["code": "PARSE_ERROR", "message": "요청을 처리할 수 없습니다."]
            ]
            if let errorData = try? JSONSerialization.data(withJSONObject: errorResponse) {
                Task { await sendRawJS(jsonData: errorData) }
            }
            return
        }

        onMessageReceived?(request)
    }

    // MARK: - Native → JS 응답

    /// RPC 응답 JSON Data를 callAsyncJavaScript로 전달
    ///
    /// evaluateJavaScript vs callAsyncJavaScript:
    /// - evaluateJavaScript: JS 코드 문자열에 데이터를 직접 보간
    ///   → "window.__bridgeResolve({\"id\":\"...\"})" (문자열 조립)
    /// - callAsyncJavaScript: arguments 딕셔너리로 데이터를 구조적으로 전달
    ///   → functionBody: "window.__bridgeResolve(response)"
    ///   → arguments: ["response": 딕셔너리]
    ///   → 데이터가 JS 코드에 삽입되지 않으므로 Injection 원천 차단
    ///
    /// async인 이유:
    /// - 호출자(ViewController DI)에 이미 Task { @MainActor in }가 존재
    /// - sync + 내부 Task를 만들면 이중 Task 중첩 + fire-and-forget (structured concurrency 파괴)
    /// - async면 기존 Task 안에서 await 체인으로 연결되어 실행 완료 추적 가능
    ///
    /// contentWorld: .page — 페이지의 JS 컨텍스트에서 실행
    /// (window.__bridgeResolve가 정의된 곳)
    func sendRawJS(jsonData: Data) async {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) else {
            print("❌ JSON 파싱 실패")
            return
        }

        if let logString = String(data: jsonData, encoding: .utf8) {
            print("📤 [Native → JS] __bridgeResolve(\(logString))")
        }

        do {
            _ = try await webView?.callAsyncJavaScript(
                "window.__bridgeResolve(response)",
                arguments: ["response": jsonObject],
                in: nil,
                in: .page
            )
        } catch {
            print("❌ JS 실행 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    /// postMessage의 body를 BridgeRequest로 디코딩
    private func decodeBridgeRequest(from body: Any) -> BridgeRequest? {
        guard let dict = body as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        return try? decoder.decode(BridgeRequest.self, from: jsonData)
    }
}

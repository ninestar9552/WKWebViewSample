//
//  BridgeHandler.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import UIKit
import WebKit

/// Native → JS 응답 전송 인터페이스
/// - ViewModel이 이 프로토콜에만 의존하여 테스트 시 Mock 교체 가능
protocol BridgeMessageSender: AnyObject {
    func sendToJS<T: Encodable>(function: String?, response: BridgeResponse<T>)
}

/// JS ↔ Native 양방향 Bridge 통신을 전담하는 핸들러 (인프라 역할)
/// - 메시지 파싱(Codable 디코딩)과 JS 응답 전송(Codable 인코딩)만 담당
/// - 비즈니스 로직은 WebViewViewModel에 위임
final class BridgeHandler: NSObject, WKScriptMessageHandler, BridgeMessageSender {

    /// JS에서 postMessage 호출 시 사용하는 핸들러 이름
    static let handlerName = "nativeBridge"

    /// evaluateJavaScript 호출을 위해 WebView 참조를 보유
    private weak var webView: WKWebView?

    /// 비즈니스 로직을 위임할 ViewModel
    weak var viewModel: WebViewViewModel?

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// WebView와 ViewModel 생성 후 참조를 주입받는 메서드
    func configure(webView: WKWebView, viewModel: WebViewViewModel) {
        self.webView = webView
        self.viewModel = viewModel
    }

    // MARK: - WKScriptMessageHandler

    /// JS에서 window.webkit.messageHandlers.nativeBridge.postMessage() 호출 시 실행
    /// - JSON → BridgeRequest Codable 디코딩으로 타입 안전성 확보
    /// - 비즈니스 로직은 ViewModel에 위임
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName else { return }

        /// Bridge 메시지의 출처를 검증하여 신뢰할 수 없는 페이지의 호출을 차단
        /// - 외부 페이지가 postMessage로 네이티브 기능에 접근하는 것을 방지
        guard SecurityConfig.isTrustedBridgeOrigin(message.frameInfo.request.url) else {
            print("[Security] 신뢰할 수 없는 출처의 Bridge 호출 차단: \(message.frameInfo.request.url?.absoluteString ?? "unknown")")
            return
        }

        print("📩 [JS → Native]\n\(message.body)")

        guard let request = decodeBridgeRequest(from: message.body) else {
            print("❌ 메시지 파싱 실패: \(message.body)")
            /// 알 수 없는 type이면 디코딩 자체가 실패하므로, callback을 수동으로 꺼내 에러 응답
            let callback = (message.body as? [String: Any])?["callback"] as? String
            sendToJS(function: callback, response: BridgeResponse(success: false, message: "요청을 처리할 수 없습니다."))
            return
        }

        viewModel?.handleBridgeMessage(request)
    }

    // MARK: - Native → JS 응답

    /// BridgeResponse를 Encodable 인코딩하여 JS 콜백 함수에 전달
    /// - 제네릭 T 덕분에 핸들러별 응답 구조체를 타입 안전하게 직렬화
    /// - callback 함수명의 유효성을 검증하여 JS Injection을 방지
    func sendToJS<T: Encodable>(function: String?, response: BridgeResponse<T>) {
        guard let function = function else { return }

        guard isValidJSFunctionName(function) else {
            print("[Security] 유효하지 않은 콜백 함수명 차단: \(function)")
            return
        }

        guard let jsonData = try? encoder.encode(response),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let jsCode = "\(function)(\(jsonString));"
        print("📤 [Native → JS]\n\(jsCode)")
        webView?.evaluateJavaScript(jsCode) { _, error in
            if let error = error {
                print("❌ JS 실행 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    /// JS 콜백 함수명의 유효성 검증 (JS Injection 방지)
    /// - 영문, 숫자, _, $, . 만 허용 (예: "receiveUserInfo", "window.callback")
    /// - 코드 삽입 시도 (세미콜론, 괄호, 공백 등)를 차단
    private func isValidJSFunctionName(_ name: String) -> Bool {
        let pattern = "^[a-zA-Z_$][a-zA-Z0-9_$.]*$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// postMessage의 body를 BridgeRequest로 디코딩
    /// - WKScriptMessage.body는 Any 타입이므로 먼저 JSON Data로 변환 후 JSONDecoder로 디코딩
    /// - BridgeRequest가 Decodable이므로 type, callback, data를 한번에 디코딩
    private func decodeBridgeRequest(from body: Any) -> BridgeRequest? {
        guard let dict = body as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        return try? decoder.decode(BridgeRequest.self, from: jsonData)
    }
}

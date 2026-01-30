//
//  BridgeHandler.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import UIKit
import WebKit

/// JS ↔ Native 양방향 Bridge 통신을 전담하는 핸들러
/// - ViewController에서 Bridge 로직을 분리하여 단일 책임 원칙(SRP) 준수
/// - WKScriptMessageHandler를 ViewController가 직접 채택하지 않고 위임하여 역할 분리
/// - final class로 선언하여 상속 방지 및 성능 최적화 (static dispatch)
final class BridgeHandler: NSObject, WKScriptMessageHandler {

    /// JS에서 postMessage 호출 시 사용하는 핸들러 이름
    /// - static let으로 선언하여 ViewController에서도 동일한 이름을 참조할 수 있도록 함
    static let handlerName = "nativeBridge"

    /// evaluateJavaScript 호출을 위해 WebView 참조를 보유
    /// - weak 참조로 순환 참조 방지 (WebView → Handler → WebView 순환 차단)
    private weak var webView: WKWebView?

    /// WebView 생성 후 참조를 주입받는 메서드
    /// - WebView는 Configuration에 Handler를 먼저 등록한 후 생성되므로, 생성자에서 주입할 수 없음
    func configure(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - WKScriptMessageHandler

    /// JS에서 window.webkit.messageHandlers.nativeBridge.postMessage() 호출 시 실행
    /// - 메시지 구조: { type: String, callback: String?, data: [String: Any] }
    /// - type: 메시지 종류 (BridgeMessageType enum으로 매핑)
    /// - callback: Native가 응답할 때 호출할 JS 함수명 (옵셔널)
    /// - data: 메시지에 담긴 데이터
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName else { return }

        print("📩 [JS → Native]\n\(message.body)")

        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let data = body["data"] as? [String: Any] else {
            print("❌ 메시지 파싱 실패: \(message.body)")
            return
        }

        // callback은 옵셔널 — JS에서 응답이 필요 없는 경우 생략 가능
        let callback = body["callback"] as? String
        handleBridgeMessage(type: type, data: data, callback: callback)
    }

    // MARK: - Message Handling

    /// type 문자열을 BridgeMessageType enum으로 변환 후 분기 처리
    /// - guard let 변환 실패 시 알 수 없는 타입으로 에러 응답 후 종료
    /// - exhaustive switch로 모든 케이스를 강제 처리 (default 없음)
    private func handleBridgeMessage(type: String, data: [String: Any], callback: String?) {
        guard let messageType = BridgeMessageType(rawValue: type) else {
            print("⚠️ 알 수 없는 메시지 타입: \(type)")
            sendToJS(function: callback, success: false, message: "요청을 처리할 수 없습니다.")
            return
        }

        switch messageType {
        case .greeting:
            if let text = data["text"] as? String {
                sendToJS(
                    function: callback,
                    success: true,
                    message: "메시지를 수신했습니다.",
                    data: ["text": "Native가 메시지를 받았습니다: \(text)"]
                )
            } else {
                sendToJS(function: callback, success: false, message: "메시지 전송에 실패했습니다.")
            }

        case .getUserInfo:
            sendToJS(
                function: callback,
                success: true,
                message: "사용자 정보를 불러왔습니다.",
                data: [
                    "name": "차순혁",
                    "device": UIDevice.current.model,
                    "osVersion": UIDevice.current.systemVersion
                ]
            )
        }
    }

    // MARK: - Native → JS 응답

    /// JS의 콜백 함수를 evaluateJavaScript로 호출하여 응답을 전달
    /// - 응답 규격: { success: Bool, message: String, data: { ... } }
    /// - success: 요청 처리 성공/실패 여부
    /// - message: 사용자에게 표시할 수 있는 안내 메시지 (팝업, 토스트 등)
    /// - data: 응답 데이터 (성공/실패 모두 포함 가능, 기본값 빈 딕셔너리)
    /// - function이 nil이면 응답하지 않음 (옵셔널 guard로 early return)
    private func sendToJS(function: String?, success: Bool, message: String, data: [String: Any] = [:]) {
        guard let function = function else { return }

        let response: [String: Any] = ["success": success, "message": message, "data": data]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let jsCode = "\(function)(\(jsonString));"
        print("📤 [Native → JS]\n\(jsCode)")
        webView?.evaluateJavaScript(jsCode) { _, error in
            if let error = error {
                print("❌ JS 실행 실패: \(error.localizedDescription)")
            }
        }
    }
}

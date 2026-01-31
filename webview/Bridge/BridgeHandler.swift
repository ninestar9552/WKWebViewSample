//
//  BridgeHandler.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import UIKit
import WebKit

/// JS ↔ Native 양방향 Bridge 통신을 전담하는 핸들러 (인프라 역할)
/// - 메시지 파싱과 JS 응답 전송만 담당
/// - 비즈니스 로직은 WebViewViewModel에 위임
final class BridgeHandler: NSObject, WKScriptMessageHandler {

    /// JS에서 postMessage 호출 시 사용하는 핸들러 이름
    static let handlerName = "nativeBridge"

    /// evaluateJavaScript 호출을 위해 WebView 참조를 보유
    private weak var webView: WKWebView?

    /// 비즈니스 로직을 위임할 ViewModel
    weak var viewModel: WebViewViewModel?

    /// WebView와 ViewModel 생성 후 참조를 주입받는 메서드
    func configure(webView: WKWebView, viewModel: WebViewViewModel) {
        self.webView = webView
        self.viewModel = viewModel
    }

    // MARK: - WKScriptMessageHandler

    /// JS에서 window.webkit.messageHandlers.nativeBridge.postMessage() 호출 시 실행
    /// - 메시지 파싱만 수행하고, 비즈니스 로직은 ViewModel에 위임
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
        viewModel?.handleBridgeMessage(type: type, data: data, callback: callback)
    }

    // MARK: - Native → JS 응답

    /// JS의 콜백 함수를 evaluateJavaScript로 호출하여 응답을 전달
    /// - ViewModel에서 호출하여 JS에 결과를 전달
    func sendToJS(function: String?, success: Bool, message: String, data: [String: Any] = [:]) {
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

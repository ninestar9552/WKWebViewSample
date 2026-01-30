//
//  ViewController.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import UIKit
import WebKit

class ViewController: UIViewController {

    // MARK: - Properties

    private let bridgeHandlerName = "nativeBridge"
    private var webView: WKWebView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        loadLocalHTML()
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: bridgeHandlerName)
    }

    // MARK: - Setup

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()

        // JS → Native Bridge 등록
        configuration.userContentController.add(self, name: bridgeHandlerName)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Load HTML
    
    private func loadLocalHTML() {
        guard let htmlURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html"
        ) else {
            print("❌ index.html 못 찾음")
            return
        }

        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    // MARK: - Native → JS 통신

    private func sendToJS(function: String?, data: [String: Any]) {
        guard let function = function,
              let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let jsCode = "\(function)(\(jsonString));"
        print("📤 [Native → JS]\n\(jsCode)")
        webView.evaluateJavaScript(jsCode) { _, error in
            if let error = error {
                print("❌ JS 실행 실패: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - WKScriptMessageHandler

extension ViewController: WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == bridgeHandlerName else { return }

        print("📩 [JS → Native]\n\(message.body)")

        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let data = body["data"] as? [String: Any] else {
            print("❌ 메시지 파싱 실패: \(message.body)")
            return
        }

        let callback = body["callback"] as? String
        handleBridgeMessage(type: type, data: data, callback: callback)
    }

    private func handleBridgeMessage(type: String, data: [String: Any], callback: String?) {
        switch type {
        case "greeting":
            if let text = data["text"] as? String {
                sendToJS(function: callback, data: ["message": "Native가 메시지를 받았습니다: \(text)"])
            }

        case "getUserInfo":
            sendToJS(function: callback, data: [
                "name": "차순혁",
                "device": UIDevice.current.model,
                "osVersion": UIDevice.current.systemVersion
            ])

        default:
            print("⚠️ 알 수 없는 메시지 타입: \(type) \(data)")
        }
    }
}

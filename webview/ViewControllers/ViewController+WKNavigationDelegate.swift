//
//  ViewController+WKNavigationDelegate.swift
//  webview
//
//  Created by 차순혁 on 2/2/26.
//

import UIKit
import WebKit

/// WebView 네비게이션 이벤트 처리
/// - 로딩 상태는 KVO estimatedProgress가 단일 소스로 관리
/// - NavigationDelegate는 에러 처리 및 URL 스킴 정책을 담당
extension ViewController: WKNavigationDelegate {

    /// URL 스킴에 따라 네비게이션 허용/차단을 결정
    /// - http/https: 화이트리스트에 등록된 도메인만 허용
    /// - file: 로컬 HTML 로딩 허용
    /// - tel, mailto 등 외부 스킴: 시스템에 위임 (전화, 메일 앱 등)
    /// - 그 외: 차단
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        switch url.scheme {
        case "file":
            /// 로컬 HTML 로딩은 별도 검증 없이 허용
            decisionHandler(SecurityConfig.allowFileScheme ? .allow : .cancel)

        case "http", "https":
            /// 화이트리스트에 등록된 도메인만 허용, 미등록 도메인은 차단
            if SecurityConfig.isDomainAllowed(url.host) {
                decisionHandler(.allow)
            } else {
                print("[Security] 차단된 도메인: \(url.host ?? "unknown")")
                decisionHandler(.cancel)
                let error = NSError(
                    domain: "WebView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "허용되지 않은 도메인입니다: \(url.host ?? "")"]
                )
                viewModel.handleError(error)
            }

        case "tel", "mailto", "sms":
            UIApplication.shared.open(url)
            decisionHandler(.cancel)

        default:
            decisionHandler(.cancel)
        }
    }

    /// HTTP 응답 상태 코드를 검사하여 4xx/5xx 에러 시 로딩을 차단
    /// - 이 메서드가 없으면 서버가 404/500을 반환해도 빈 페이지를 그대로 표시
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard let httpResponse = navigationResponse.response as? HTTPURLResponse else {
            decisionHandler(.allow)
            return
        }

        print("navigationResponse statusCode: \(httpResponse.statusCode)")

        if httpResponse.statusCode >= 400 {
            decisionHandler(.cancel)
            let error = NSError(
                domain: "WebView",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) 오류가 발생했습니다."]
            )
            viewModel.handleError(error)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("didFailProvisionalNavigation \(error)")
        viewModel.handleError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("didFail \(error)")
        viewModel.handleError(error)
    }
}

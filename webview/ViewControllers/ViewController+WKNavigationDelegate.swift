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
///
/// MVVM → TCA 변경점:
/// - viewModel.handleError(error) → store.send(.errorOccurred(error.localizedDescription))
/// - 나머지 로직(URL 스킴 검사, HTTP 상태 검사 등)은 그대로 유지
extension ViewController: WKNavigationDelegate {

    /// URL 스킴에 따라 네비게이션 허용/차단을 결정
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        switch url.scheme {
        case "file":
            decisionHandler(SecurityConfig.allowFileScheme ? .allow : .cancel)

        case "http", "https":
            if SecurityConfig.isDomainAllowed(url.host) {
                decisionHandler(.allow)
            } else {
                print("[Security] 차단된 도메인: \(url.host ?? "unknown")")
                decisionHandler(.cancel)
                /// MVVM: viewModel.handleError(error)
                /// TCA: store.send(.errorOccurred(message))
                store.send(.errorOccurred("허용되지 않은 도메인입니다: \(url.host ?? "")"))
            }

        case "tel", "mailto", "sms":
            UIApplication.shared.open(url)
            decisionHandler(.cancel)

        default:
            decisionHandler(.cancel)
        }
    }

    /// HTTP 응답 상태 코드를 검사하여 4xx/5xx 에러 시 로딩을 차단
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        guard let httpResponse = navigationResponse.response as? HTTPURLResponse else {
            decisionHandler(.allow)
            return
        }

        print("navigationResponse statusCode: \(httpResponse.statusCode)")

        if httpResponse.statusCode >= 400 {
            decisionHandler(.cancel)
            /// MVVM: viewModel.handleError(error)
            /// TCA: store.send(.errorOccurred(message))
            store.send(.errorOccurred("HTTP \(httpResponse.statusCode) 오류가 발생했습니다."))
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("didFailProvisionalNavigation \(error)")
        /// MVVM: viewModel.handleError(error)
        /// TCA: store.send(.errorOccurred(error.localizedDescription))
        store.send(.errorOccurred(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("didFail \(error)")
        store.send(.errorOccurred(error.localizedDescription))
    }

    /// 페이지 로딩 완료 시 현재 URL을 저장 (백화현상 복구용)
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url, url.absoluteString != "about:blank" {
            lastLoadedURL = url
        }
    }

    /// WKWebView 콘텐츠 프로세스가 종료되었을 때 호출 (백화현상)
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("⚠️ WebContent Process Terminated (백화현상)")
        needsReload = true
    }
}

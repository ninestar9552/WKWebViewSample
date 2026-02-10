//
//  ViewController+WKUIDelegate.swift
//  webview
//
//  Created by 차순혁 on 2/2/26.
//

import UIKit
import WebKit

/// WKWebView UI 관련 이벤트 처리
/// - JS alert/confirm/prompt → 네이티브 UIAlertController
/// - window.open() → 팝업 ViewController 생성
/// - window.close() → 팝업 dismiss
extension ViewController: WKUIDelegate {

    // MARK: - 새 창 열기/닫기

    /// JS window.open() 또는 target="_blank" 링크 클릭 시 호출
    /// - 전달받은 configuration 객체를 그대로 사용 (WebKit이 동일 객체 여부 검증)
    /// - 반환한 WebView에 WebKit이 해당 페이지를 로드
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        print("createWebViewWith: \(navigationAction.request.url?.absoluteString ?? "nil")")

        let popupVC = ViewController(configuration: configuration)
        popupVC.modalPresentationStyle = .overFullScreen
        present(popupVC, animated: true)

        return popupVC.webView
    }

    /// JS window.close() 호출 시 실행
    /// - 팝업 모드일 때 자기 자신을 dismiss
    /// - 부모 창에서 popup.close() 호출 시에도 팝업의 이 메서드가 호출됨
    func webViewDidClose(_ webView: WKWebView) {
        print("webViewDidClose")
        dismiss(animated: true)
    }

    // MARK: - JS Dialog

    /// JS alert() → 네이티브 알럿
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }

    /// JS confirm() → 확인/취소 알럿, 사용자 선택에 따라 true/false 반환
    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }

    /// JS prompt() → 텍스트 입력 알럿, 입력값 또는 nil 반환
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
}

//
//  WebViewViewModel.swift
//  webview
//
//  Created by 차순혁 on 1/31/26.
//

import UIKit
import Combine

/// WebView 화면의 비즈니스 로직과 상태를 관리하는 ViewModel
/// - BridgeHandler에서 파싱된 메시지를 받아 비즈니스 로직을 처리
/// - @Published 프로퍼티를 통해 ViewController에 상태 변경을 전달
final class WebViewViewModel {

    // MARK: - Published State

    /// KVO estimatedProgress 값을 반영하는 로딩 진행률 (0.0 ~ 1.0)
    @Published var loadProgress: Double = 0.0

    /// NavigationDelegate에서 전달받은 에러
    @Published var error: Error? = nil

    // MARK: - Dependencies

    private weak var bridgeHandler: BridgeHandler?

    // MARK: - Configuration

    /// BridgeHandler 참조를 주입받는 메서드
    /// - ViewModel이 JS 응답을 보낼 때 bridgeHandler.sendToJS()를 호출하기 위해 필요
    func configure(bridgeHandler: BridgeHandler) {
        self.bridgeHandler = bridgeHandler
    }

    // MARK: - Bridge Message Handling

    /// BridgeHandler에서 파싱된 메시지를 받아 비즈니스 로직을 처리
    /// - type 문자열을 BridgeMessageType enum으로 변환 후 분기 처리
    /// - 처리 결과를 bridgeHandler.sendToJS()로 JS에 응답
    func handleBridgeMessage(type: String, data: [String: Any], callback: String?) {
        guard let messageType = BridgeMessageType(rawValue: type) else {
            print("⚠️ 알 수 없는 메시지 타입: \(type)")
            bridgeHandler?.sendToJS(function: callback, success: false, message: "요청을 처리할 수 없습니다.")
            return
        }

        switch messageType {
        case .greeting:
            handleGreeting(data: data, callback: callback)

        case .getUserInfo:
            handleGetUserInfo(callback: callback)
        }
    }

    // MARK: - Loading State

    /// KVO estimatedProgress 값을 @Published로 반영
    func updateLoadProgress(_ progress: Double) {
        self.loadProgress = progress
    }

    /// 네비게이션 에러 발생 시 로딩 상태를 초기화하고 에러를 전달
    func handleError(_ error: Error) {
        self.loadProgress = 0.0
        self.error = error
    }

    // MARK: - Private Handlers

    private func handleGreeting(data: [String: Any], callback: String?) {
        if let text = data["text"] as? String {
            bridgeHandler?.sendToJS(
                function: callback,
                success: true,
                message: "메시지를 수신했습니다.",
                data: ["text": "\(text)"]
            )
        } else {
            bridgeHandler?.sendToJS(function: callback, success: false, message: "메시지 전송에 실패했습니다.")
        }
    }

    private func handleGetUserInfo(callback: String?) {
        bridgeHandler?.sendToJS(
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

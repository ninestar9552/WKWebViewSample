//
//  WebViewViewModelTests.swift
//  webviewTests
//
//  Created by 차순혁 on 2/7/26.
//

import Testing
import Foundation
import Combine
@testable import webview

// MARK: - Mock

/// ViewModel이 sendToJS를 호출하는지 검증하기 위한 Mock
final class MockBridgeMessageSender: BridgeMessageSender {
    struct Call {
        let function: String?
        let success: Bool
        let message: String
    }

    private(set) var calls: [Call] = []

    func sendToJS<T: Encodable>(function: String?, response: BridgeResponse<T>) {
        calls.append(Call(function: function, success: response.success, message: response.message))
    }

    var lastCall: Call? { calls.last }
}

// MARK: - Helper

private func makeRequest(
    type: String,
    callback: String? = "testCallback",
    data: [String: Any]? = nil
) -> BridgeRequest? {
    var dict: [String: Any] = ["type": type]
    if let callback { dict["callback"] = callback }
    if let data { dict["data"] = data }
    guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
    return try? JSONDecoder().decode(BridgeRequest.self, from: jsonData)
}

// MARK: - Tests

struct WebViewViewModelTests {

    // MARK: - greeting

    @Test func handleGreeting_유효한_데이터_success_응답() {
        let mock = MockBridgeMessageSender()
        let vm = WebViewViewModel()
        vm.configure(bridgeHandler: mock)

        let request = makeRequest(type: "greeting", data: ["text": "Hello", "timestamp": "2026-02-07"])!
        vm.handleBridgeMessage(request)

        #expect(mock.lastCall?.success == true)
        #expect(mock.lastCall?.function == "testCallback")
    }

    @Test func handleGreeting_데이터_없음_failure_응답() {
        let mock = MockBridgeMessageSender()
        let vm = WebViewViewModel()
        vm.configure(bridgeHandler: mock)

        let request = makeRequest(type: "greeting")!
        vm.handleBridgeMessage(request)

        #expect(mock.lastCall?.success == false)
    }

    // MARK: - getUserInfo

    @Test func handleGetUserInfo_success_응답() {
        let mock = MockBridgeMessageSender()
        let vm = WebViewViewModel()
        vm.configure(bridgeHandler: mock)

        let request = makeRequest(type: "getUserInfo")!
        vm.handleBridgeMessage(request)

        #expect(mock.lastCall?.success == true)
        #expect(mock.lastCall?.function == "testCallback")
    }

    // MARK: - getAppVersion

    @Test func handleGetAppVersion_success_응답() {
        let mock = MockBridgeMessageSender()
        let vm = WebViewViewModel()
        vm.configure(bridgeHandler: mock)

        let request = makeRequest(type: "getAppVersion")!
        vm.handleBridgeMessage(request)

        #expect(mock.lastCall?.success == true)
    }

    // MARK: - openUrl

    @Test func handleOpenUrl_유효한_URL_이벤트_발행() {
        let mock = MockBridgeMessageSender()
        let vm = WebViewViewModel()
        vm.configure(bridgeHandler: mock)

        var receivedURL: URL?
        var cancellables = Set<AnyCancellable>()

        vm.$urlToOpen
            .sink { receivedURL = $0 }
            .store(in: &cancellables)

        let request = makeRequest(type: "openUrl", data: ["url": "https://www.apple.com"])!
        vm.handleBridgeMessage(request)

        #expect(mock.lastCall?.success == true)
        #expect(receivedURL?.absoluteString == "https://www.apple.com")
    }

    @Test func handleOpenUrl_잘못된_URL_failure_응답() {
        let mock = MockBridgeMessageSender()
        let vm = WebViewViewModel()
        vm.configure(bridgeHandler: mock)

        let request = makeRequest(type: "openUrl", data: ["url": ""])!
        vm.handleBridgeMessage(request)

        #expect(mock.lastCall?.success == false)
    }

    @Test func handleOpenUrl_데이터_없음_failure_응답() {
        let mock = MockBridgeMessageSender()
        let vm = WebViewViewModel()
        vm.configure(bridgeHandler: mock)

        let request = makeRequest(type: "openUrl")!
        vm.handleBridgeMessage(request)

        #expect(mock.lastCall?.success == false)
    }

    // MARK: - showToast

    @Test func handleShowToast_유효한_메시지_이벤트_발행() {
        let mock = MockBridgeMessageSender()
        let vm = WebViewViewModel()
        vm.configure(bridgeHandler: mock)

        var receivedMessage: String?
        var cancellables = Set<AnyCancellable>()

        vm.$toastMessage
            .sink { receivedMessage = $0 }
            .store(in: &cancellables)

        let request = makeRequest(type: "showToast", data: ["message": "저장되었습니다"])!
        vm.handleBridgeMessage(request)

        #expect(mock.lastCall?.success == true)
        #expect(receivedMessage == "저장되었습니다")
    }

    @Test func handleShowToast_데이터_없음_failure_응답() {
        let mock = MockBridgeMessageSender()
        let vm = WebViewViewModel()
        vm.configure(bridgeHandler: mock)

        let request = makeRequest(type: "showToast")!
        vm.handleBridgeMessage(request)

        #expect(mock.lastCall?.success == false)
    }

    // MARK: - Loading State

    @Test func updateLoadProgress_값_반영() {
        let vm = WebViewViewModel()

        var receivedProgress: Double?
        var cancellables = Set<AnyCancellable>()

        vm.$loadProgress
            .sink { receivedProgress = $0 }
            .store(in: &cancellables)

        vm.updateLoadProgress(0.5)
        #expect(receivedProgress == 0.5)
    }

    @Test func handleError_progress_초기화_및_에러_전달() {
        let vm = WebViewViewModel()

        var receivedError: Error?
        var receivedProgress: Double?
        var cancellables = Set<AnyCancellable>()

        vm.$error
            .compactMap { $0 }
            .sink { receivedError = $0 }
            .store(in: &cancellables)

        vm.$loadProgress
            .sink { receivedProgress = $0 }
            .store(in: &cancellables)

        vm.updateLoadProgress(0.7)
        let error = NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "테스트 에러"])
        vm.handleError(error)

        #expect(receivedError?.localizedDescription == "테스트 에러")
        #expect(receivedProgress == 0.0)
    }
}

//
//  WebViewFeatureTests.swift
//  webviewTests
//
//  Created by TCA 변환 on 2/11/26.
//

import Testing
import Foundation
import ComposableArchitecture
@testable import webview

// ============================================================================
// MARK: - MVVM vs TCA: 테스트 방식 비교
// ============================================================================
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ MVVM (기존 WebViewViewModelTests)                                       │
// │                                                                         │
// │ 1. Mock 클래스 생성:                                                     │
// │    class MockBridgeMessageSender: BridgeMessageSender { ... }           │
// │                                                                         │
// │ 2. ViewModel 생성 + Mock 주입:                                           │
// │    let vm = WebViewViewModel()                                          │
// │    vm.configure(bridgeHandler: mock)                                    │
// │                                                                         │
// │ 3. 메서드 호출 후 Mock/Combine으로 결과 검증:                              │
// │    vm.handleBridgeMessage(request)                                      │
// │    #expect(mock.lastCall?.success == true)                              │
// ├─────────────────────────────────────────────────────────────────────────┤
// │ TCA (이 파일 — WebViewFeatureTests)                                     │
// │                                                                         │
// │ 1. Mock 클래스 불필요 — TestStore가 대체:                                 │
// │    let store = TestStore(initialState: ...) { WebViewFeature() }        │
// │                                                                         │
// │ 2. Dependency 오버라이드 (클로저 한 줄):                                  │
// │    store.dependencies.bridgeClient = BridgeClient(sendRawJS: { ... })   │
// │                                                                         │
// │ 3. send → receive 패턴으로 선언적 검증:                                   │
// │    await store.send(.bridgeMessageReceived(request)) {                  │
// │        $0.urlToOpen = URL(string: "...")  ← 예상 상태 변경을 선언        │
// │    }                                                                    │
// │                                                                         │
// │ 장점:                                                                    │
// │ - Mock 클래스 작성 불필요                                                 │
// │ - 상태 변경을 "선언적"으로 검증 (어떤 상태가 어떻게 바뀌는지)              │
// │ - 처리되지 않은 Effect가 있으면 테스트가 자동으로 실패                     │
// └─────────────────────────────────────────────────────────────────────────┘

// MARK: - Helper

/// BridgeRequest를 딕셔너리로부터 생성하는 헬퍼
/// - MVVM/TCA 모두 동일한 BridgeRequest를 사용하므로 헬퍼도 동일
@MainActor private func makeRequest(
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

/// sendRawJS 호출을 기록하는 타입 별칭
/// - MVVM: MockBridgeMessageSender.calls 배열
/// - TCA: LockIsolated로 래핑하여 @Sendable 클로저에서도 안전하게 기록
private typealias SentCall = (function: String?, jsonString: String)

// MARK: - Tests

@MainActor struct WebViewFeatureTests {

    // MARK: - greeting

    /// MVVM 원본:
    /// let mock = MockBridgeMessageSender()
    /// let vm = WebViewViewModel()
    /// vm.configure(bridgeHandler: mock)
    /// vm.handleBridgeMessage(request)
    /// #expect(mock.lastCall?.success == true)
    @Test func greeting_유효한_데이터_success_응답() async {
        /// LockIsolated: swift-dependencies 제공 스레드 안전 래퍼
        /// - MVVM: var calls 배열에 직접 기록 (단일 스레드)
        /// - TCA: BridgeClient.sendRawJS가 @Sendable이므로 LockIsolated 필요
        ///   Swift 6 strict concurrency에서 var 캡처가 금지되기 때문
        let sentCalls = LockIsolated<[SentCall]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            /// MVVM: Mock 클래스의 sendToJS가 calls 배열에 기록
            /// TCA: BridgeClient.sendRawJS 클로저에서 직접 기록 — Mock 클래스 불필요
            $0.bridgeClient = BridgeClient(sendRawJS: { function, jsonString in
                sentCalls.withValue { $0.append((function, jsonString)) }
            })
        }

        let request = makeRequest(type: "greeting", data: ["text": "Hello", "timestamp": "2026-02-07"])!

        /// MVVM: vm.handleBridgeMessage(request)
        /// TCA: store.send(.bridgeMessageReceived(request))
        /// → 상태 변경이 없으면 클로저 생략 가능
        await store.send(.bridgeMessageReceived(request))

        /// Effect(bridgeClient.send)가 완료될 때까지 대기
        /// - MVVM에서는 Mock의 calls 배열을 바로 확인했지만
        /// - TCA에서는 Effect가 비동기이므로 완료를 기다려야 함
        /// - exhaustivity: .off → Effect가 추가 액션을 보내지 않으므로 생략 가능
        #expect(sentCalls.value.count == 1)
        #expect(sentCalls.value[0].function == "testCallback")
        #expect(sentCalls.value[0].jsonString.contains("\"success\":true"))
    }

    @Test func greeting_데이터_없음_failure_응답() async {
        let sentCalls = LockIsolated<[SentCall]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { function, jsonString in
                sentCalls.withValue { $0.append((function, jsonString)) }
            })
        }

        let request = makeRequest(type: "greeting")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentCalls.value.count == 1)
        #expect(sentCalls.value[0].jsonString.contains("\"success\":false"))
    }

    // MARK: - getUserInfo

    @Test func getUserInfo_success_응답() async {
        let sentCalls = LockIsolated<[SentCall]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { function, jsonString in
                sentCalls.withValue { $0.append((function, jsonString)) }
            })
        }

        let request = makeRequest(type: "getUserInfo")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentCalls.value.count == 1)
        #expect(sentCalls.value[0].function == "testCallback")
        #expect(sentCalls.value[0].jsonString.contains("\"success\":true"))
    }

    // MARK: - getAppVersion

    @Test func getAppVersion_success_응답() async {
        let sentCalls = LockIsolated<[SentCall]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { function, jsonString in
                sentCalls.withValue { $0.append((function, jsonString)) }
            })
        }

        let request = makeRequest(type: "getAppVersion")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentCalls.value.count == 1)
        #expect(sentCalls.value[0].jsonString.contains("\"success\":true"))
    }

    // MARK: - openUrl

    /// MVVM 원본:
    /// vm.$urlToOpen.sink { receivedURL = $0 }
    /// vm.handleBridgeMessage(request)
    /// #expect(receivedURL?.absoluteString == "https://www.apple.com")
    ///
    /// TCA: store.send 클로저에서 예상 상태 변경을 선언적으로 검증
    @Test func openUrl_유효한_URL_상태_변경() async {
        let sentCalls = LockIsolated<[SentCall]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { function, jsonString in
                sentCalls.withValue { $0.append((function, jsonString)) }
            })
        }

        let request = makeRequest(type: "openUrl", data: ["url": "https://www.apple.com"])!

        /// TCA의 핵심: send 클로저에서 "이 액션이 State를 이렇게 바꿔야 한다"를 선언
        /// - MVVM: Combine .sink로 받은 값을 수동 비교
        /// - TCA: $0 mutation으로 예상 상태를 선언 → 일치하지 않으면 자동 실패
        await store.send(.bridgeMessageReceived(request)) {
            $0.urlToOpen = URL(string: "https://www.apple.com")
        }

        #expect(sentCalls.value.count == 1)
        #expect(sentCalls.value[0].jsonString.contains("\"success\":true"))
    }

    @Test func openUrl_잘못된_URL_failure_응답() async {
        let sentCalls = LockIsolated<[SentCall]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { function, jsonString in
                sentCalls.withValue { $0.append((function, jsonString)) }
            })
        }

        let request = makeRequest(type: "openUrl", data: ["url": ""])!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentCalls.value.count == 1)
        #expect(sentCalls.value[0].jsonString.contains("\"success\":false"))
    }

    @Test func openUrl_데이터_없음_failure_응답() async {
        let sentCalls = LockIsolated<[SentCall]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { function, jsonString in
                sentCalls.withValue { $0.append((function, jsonString)) }
            })
        }

        let request = makeRequest(type: "openUrl")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentCalls.value.count == 1)
        #expect(sentCalls.value[0].jsonString.contains("\"success\":false"))
    }

    // MARK: - showToast

    @Test func showToast_유효한_메시지_상태_변경() async {
        let sentCalls = LockIsolated<[SentCall]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { function, jsonString in
                sentCalls.withValue { $0.append((function, jsonString)) }
            })
        }

        let request = makeRequest(type: "showToast", data: ["message": "저장되었습니다"])!

        await store.send(.bridgeMessageReceived(request)) {
            $0.toastMessage = "저장되었습니다"
        }

        #expect(sentCalls.value.count == 1)
        #expect(sentCalls.value[0].jsonString.contains("\"success\":true"))
    }

    @Test func showToast_데이터_없음_failure_응답() async {
        let sentCalls = LockIsolated<[SentCall]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { function, jsonString in
                sentCalls.withValue { $0.append((function, jsonString)) }
            })
        }

        let request = makeRequest(type: "showToast")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentCalls.value.count == 1)
        #expect(sentCalls.value[0].jsonString.contains("\"success\":false"))
    }

    // MARK: - Loading State

    /// MVVM 원본:
    /// vm.updateLoadProgress(0.5)
    /// #expect(receivedProgress == 0.5)
    ///
    /// TCA: store.send(.progressUpdated(0.5)) { $0.loadProgress = 0.5 }
    /// → 선언적으로 "이 액션이 상태를 이렇게 바꿔야 한다"를 검증
    @Test func progressUpdated_상태_반영() async {
        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        }

        await store.send(.progressUpdated(0.5)) {
            $0.loadProgress = 0.5
        }
    }

    @Test func errorOccurred_progress_초기화_및_에러_설정() async {
        /// 초기 상태를 미리 설정 (progress가 0.7인 상태에서 에러 발생)
        let store = TestStore(initialState: WebViewFeature.State(loadProgress: 0.7)) {
            WebViewFeature()
        }

        /// MVVM: vm.handleError(error) → progress = 0.0, error = error
        /// TCA: store.send(.errorOccurred("테스트 에러")) → progress = 0.0, errorMessage = "테스트 에러"
        await store.send(.errorOccurred("테스트 에러")) {
            $0.loadProgress = 0.0
            $0.errorMessage = "테스트 에러"
        }
    }

    // MARK: - Event Consumption (TCA에서 추가된 테스트)

    /// MVVM에서는 @Event가 자동 소비되어 이런 테스트가 불필요했음
    /// TCA에서는 Optional State를 명시적으로 nil로 초기화하는 액션을 검증

    @Test func errorDismissed_상태_초기화() async {
        let store = TestStore(
            initialState: WebViewFeature.State(errorMessage: "기존 에러")
        ) {
            WebViewFeature()
        }

        await store.send(.errorDismissed) {
            $0.errorMessage = nil
        }
    }

    @Test func urlOpened_상태_초기화() async {
        let store = TestStore(
            initialState: WebViewFeature.State(urlToOpen: URL(string: "https://example.com"))
        ) {
            WebViewFeature()
        }

        await store.send(.urlOpened) {
            $0.urlToOpen = nil
        }
    }

    @Test func toastShown_상태_초기화() async {
        let store = TestStore(
            initialState: WebViewFeature.State(toastMessage: "기존 메시지")
        ) {
            WebViewFeature()
        }

        await store.send(.toastShown) {
            $0.toastMessage = nil
        }
    }
}

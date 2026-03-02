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
/// - Callback 기반: makeRequest(type:callback:data:)
/// - RPC 기반: makeRequest(method:id:params:)
@MainActor private func makeRequest(
    method: String,
    id: String = "test-uuid",
    params: [String: Any]? = nil
) -> BridgeRequest? {
    var dict: [String: Any] = ["id": id, "method": method]
    if let params { dict["params"] = params }
    guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
    return try? JSONDecoder().decode(BridgeRequest.self, from: jsonData)
}

/// sendRawJS로 전송된 Data를 딕셔너리로 디코딩하는 헬퍼
/// - Callback 기반: jsonString.contains("\"success\":true") 문자열 검색
/// - RPC 기반: Data → Dictionary로 디코딩하여 result/error 키로 구조적 검증
private func decodeResponse(_ data: Data) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

// MARK: - Tests

@MainActor struct WebViewFeatureTests {

    // MARK: - greeting

    /// MVVM 원본:
    /// let mock = MockBridgeMessageSender()
    /// let vm = WebViewViewModel()
    /// vm.configure(bridgeHandler: mock)
    /// vm.handleBridgeMessage(request)
    /// #expect(mock.lastCall?.success == true)
    @Test func greeting_유효한_데이터_result_응답() async {
        /// LockIsolated: swift-dependencies 제공 스레드 안전 래퍼
        /// - MVVM: var calls 배열에 직접 기록 (단일 스레드)
        /// - TCA: BridgeClient.sendRawJS가 @Sendable이므로 LockIsolated 필요
        ///   Swift 6 strict concurrency에서 var 캡처가 금지되기 때문
        let sentData = LockIsolated<[Data]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            /// MVVM: Mock 클래스의 sendToJS가 calls 배열에 기록
            /// TCA: BridgeClient.sendRawJS 클로저에서 직접 기록 — Mock 클래스 불필요
            $0.bridgeClient = BridgeClient(sendRawJS: { jsonData in
                sentData.withValue { $0.append(jsonData) }
            })
        }

        let request = makeRequest(method: "greeting", params: ["text": "Hello", "timestamp": "2026-02-07"])!

        /// MVVM: vm.handleBridgeMessage(request)
        /// TCA: store.send(.bridgeMessageReceived(request))
        /// → 상태 변경이 없으면 클로저 생략 가능
        await store.send(.bridgeMessageReceived(request))

        #expect(sentData.value.count == 1)
        let response = decodeResponse(sentData.value[0])
        #expect(response?["id"] as? String == "test-uuid")
        #expect(response?["result"] != nil)
        #expect(response?["error"] == nil)
    }

    @Test func greeting_데이터_없음_error_응답() async {
        let sentData = LockIsolated<[Data]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { jsonData in
                sentData.withValue { $0.append(jsonData) }
            })
        }

        let request = makeRequest(method: "greeting")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentData.value.count == 1)
        let response = decodeResponse(sentData.value[0])
        #expect(response?["id"] as? String == "test-uuid")
        let error = response?["error"] as? [String: Any]
        #expect(error?["code"] as? String == "INVALID_PARAMS")
    }

    // MARK: - getUserInfo

    @Test func getUserInfo_result_응답() async {
        let sentData = LockIsolated<[Data]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { jsonData in
                sentData.withValue { $0.append(jsonData) }
            })
        }

        let request = makeRequest(method: "getUserInfo")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentData.value.count == 1)
        let response = decodeResponse(sentData.value[0])
        #expect(response?["id"] as? String == "test-uuid")
        #expect(response?["result"] != nil)
    }

    // MARK: - getAppVersion

    @Test func getAppVersion_result_응답() async {
        let sentData = LockIsolated<[Data]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { jsonData in
                sentData.withValue { $0.append(jsonData) }
            })
        }

        let request = makeRequest(method: "getAppVersion")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentData.value.count == 1)
        let response = decodeResponse(sentData.value[0])
        #expect(response?["result"] != nil)
    }

    // MARK: - openUrl

    /// MVVM 원본:
    /// vm.$urlToOpen.sink { receivedURL = $0 }
    /// vm.handleBridgeMessage(request)
    /// #expect(receivedURL?.absoluteString == "https://www.apple.com")
    ///
    /// TCA: store.send 클로저에서 예상 상태 변경을 선언적으로 검증
    @Test func openUrl_유효한_URL_상태_변경() async {
        let sentData = LockIsolated<[Data]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { jsonData in
                sentData.withValue { $0.append(jsonData) }
            })
        }

        let request = makeRequest(method: "openUrl", params: ["url": "https://www.apple.com"])!

        /// TCA의 핵심: send 클로저에서 "이 액션이 State를 이렇게 바꿔야 한다"를 선언
        /// - MVVM: Combine .sink로 받은 값을 수동 비교
        /// - TCA: $0 mutation으로 예상 상태를 선언 → 일치하지 않으면 자동 실패
        await store.send(.bridgeMessageReceived(request)) {
            $0.urlToOpen = URL(string: "https://www.apple.com")
        }

        #expect(sentData.value.count == 1)
        let response = decodeResponse(sentData.value[0])
        #expect(response?["result"] != nil)
        #expect(response?["error"] == nil)
    }

    @Test func openUrl_잘못된_URL_error_응답() async {
        let sentData = LockIsolated<[Data]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { jsonData in
                sentData.withValue { $0.append(jsonData) }
            })
        }

        let request = makeRequest(method: "openUrl", params: ["url": ""])!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentData.value.count == 1)
        let response = decodeResponse(sentData.value[0])
        let error = response?["error"] as? [String: Any]
        #expect(error?["code"] as? String == "INVALID_PARAMS")
    }

    @Test func openUrl_데이터_없음_error_응답() async {
        let sentData = LockIsolated<[Data]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { jsonData in
                sentData.withValue { $0.append(jsonData) }
            })
        }

        let request = makeRequest(method: "openUrl")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentData.value.count == 1)
        let response = decodeResponse(sentData.value[0])
        let error = response?["error"] as? [String: Any]
        #expect(error?["code"] as? String == "INVALID_PARAMS")
    }

    // MARK: - showToast

    @Test func showToast_유효한_메시지_상태_변경() async {
        let sentData = LockIsolated<[Data]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { jsonData in
                sentData.withValue { $0.append(jsonData) }
            })
        }

        let request = makeRequest(method: "showToast", params: ["message": "저장되었습니다"])!

        await store.send(.bridgeMessageReceived(request)) {
            $0.toastMessage = "저장되었습니다"
        }

        #expect(sentData.value.count == 1)
        let response = decodeResponse(sentData.value[0])
        #expect(response?["result"] != nil)
        #expect(response?["error"] == nil)
    }

    @Test func showToast_데이터_없음_error_응답() async {
        let sentData = LockIsolated<[Data]>([])

        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        } withDependencies: {
            $0.bridgeClient = BridgeClient(sendRawJS: { jsonData in
                sentData.withValue { $0.append(jsonData) }
            })
        }

        let request = makeRequest(method: "showToast")!
        await store.send(.bridgeMessageReceived(request))

        #expect(sentData.value.count == 1)
        let response = decodeResponse(sentData.value[0])
        let error = response?["error"] as? [String: Any]
        #expect(error?["code"] as? String == "INVALID_PARAMS")
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

    // MARK: - White Screen Recovery State Machine

    @Test func pageDidFinish_유효_URL_로드상태로_전이() async {
        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        }
        let url = URL(string: "https://www.apple.com")!

        await store.send(.pageDidFinish(url)) {
            $0.recoveryState = .loaded(url)
        }
    }

    @Test func terminated_후_didBecomeActive_복구필요상태로_전이() async {
        let url = URL(string: "https://www.apple.com")!
        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        }

        await store.send(.pageDidFinish(url)) {
            $0.recoveryState = .loaded(url)
        }

        await store.send(.webContentProcessDidTerminate) {
            $0.recoveryState = .terminated(lastURL: url)
        }

        await store.send(.appDidBecomeActive) {
            $0.recoveryState = .needsRecovery(lastURL: url)
        }
    }

    /// 전이 단위 테스트:
    /// recovering 진입 자체가 깨졌는지 빠르게 식별하기 위해 분리
    @Test func recoveryLoadStarted_복구요청상태에서_recovering으로_전이() async {
        let url = URL(string: "https://www.apple.com")!
        let store = TestStore(
            initialState: WebViewFeature.State(
                recoveryState: .needsRecovery(lastURL: url)
            )
        ) {
            WebViewFeature()
        }

        await store.send(.recoveryLoadStarted) {
            $0.recoveryState = .recovering(lastURL: url)
        }
    }

    @Test func recovering_후_didBecomeActive_복구요청상태로_재진입() async {
        let url = URL(string: "https://www.apple.com")!
        let store = TestStore(
            initialState: WebViewFeature.State(
                recoveryState: .recovering(lastURL: url)
            )
        ) {
            WebViewFeature()
        }

        await store.send(.appDidBecomeActive) {
            $0.recoveryState = .needsRecovery(lastURL: url)
        }
    }

    /// 통합 전이 테스트:
    /// loaded -> terminated -> needsRecovery -> recovering -> loaded 전체 고리 검증
    @Test func 백화현상_복구_전체흐름_recovering에서_loaded까지_전이() async {
        let url = URL(string: "https://www.apple.com")!
        let store = TestStore(initialState: WebViewFeature.State()) {
            WebViewFeature()
        }

        await store.send(.pageDidFinish(url)) {
            $0.recoveryState = .loaded(url)
        }

        await store.send(.webContentProcessDidTerminate) {
            $0.recoveryState = .terminated(lastURL: url)
        }

        await store.send(.appDidBecomeActive) {
            $0.recoveryState = .needsRecovery(lastURL: url)
        }

        await store.send(.recoveryLoadStarted) {
            $0.recoveryState = .recovering(lastURL: url)
        }

        await store.send(.pageDidFinish(url)) {
            $0.recoveryState = .loaded(url)
        }
    }

    @Test func terminated_lastURL없음_didBecomeActive_복구미시도() async {
        let store = TestStore(
            initialState: WebViewFeature.State(recoveryState: .terminated(lastURL: nil))
        ) {
            WebViewFeature()
        }

        await store.send(.appDidBecomeActive)
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

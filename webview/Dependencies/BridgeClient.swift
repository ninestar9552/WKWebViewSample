//
//  BridgeClient.swift
//  webview
//
//  Created by TCA 변환 on 2/11/26.
//

import Foundation
import ComposableArchitecture

// ============================================================================
// MARK: - MVVM vs TCA: 의존성 주입 방식 비교
// ============================================================================
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ MVVM (기존)                                                             │
// │                                                                         │
// │ 1. 프로토콜을 정의:                                                       │
// │    protocol BridgeMessageSender: AnyObject {                            │
// │        func sendToJS<T: Encodable>(function: String?, response: ...)    │
// │    }                                                                    │
// │                                                                         │
// │ 2. ViewModel이 프로토콜에 의존:                                            │
// │    private weak var bridgeHandler: (any BridgeMessageSender)?           │
// │                                                                         │
// │ 3. 테스트 시 Mock 클래스를 직접 구현:                                       │
// │    class MockBridgeMessageSender: BridgeMessageSender { ... }           │
// ├─────────────────────────────────────────────────────────────────────────┤
// │ TCA (변환 후)                                                            │
// │                                                                         │
// │ 1. struct + 클로저로 의존성 정의:                                          │
// │    struct BridgeClient { var sendRawJS: (...) -> Void }                 │
// │                                                                         │
// │ 2. Reducer에서 @Dependency로 주입:                                       │
// │    @Dependency(\.bridgeClient) var bridgeClient                         │
// │                                                                         │
// │ 3. 테스트 시 withDependencies로 교체:                                     │
// │    store.dependencies.bridgeClient = BridgeClient(sendRawJS: { ... })   │
// └─────────────────────────────────────────────────────────────────────────┘
//
// 장점:
// - Mock 클래스를 매번 만들 필요 없음 → 클로저 하나로 해결
// - 의존성이 명시적으로 선언됨 → 어떤 외부 리소스를 쓰는지 한눈에 파악
// - 테스트에서 의존성을 빠뜨리면 런타임에 경고 → 실수 방지

// ============================================================================
// MARK: - @DependencyClient 매크로 버전 (비교용)
// ============================================================================
//
// 최신 TCA(1.x 이상)에서 @DependencyClient 매크로가 자동으로 해주는 일:
// ✅ Memberwise init 생성 (전체 파라미터 + endpoint 제외 두 가지)
// ✅ @DependencyEndpoint 자동 추가 → unimplemented 기본값 + 편의 메서드 생성
// ✅ 테스트에서 호출 안 된 endpoint 감지 (unimplemented → XCTFail)
// ✅ DependencyKey conformance (liveValue / testValue) 자동 생성
// ✅ DependencyValues extension (get / set) 자동 생성
//
// 즉, 아래처럼 struct 선언 + 편의 메서드만 작성하면 끝:
//
// @DependencyClient
// struct BridgeClient: Sendable {
//     var sendRawJS: @Sendable (_ function: String?, _ jsonString: String) -> Void
// }
//
// // 편의 메서드만 직접 작성
// extension BridgeClient {
//     func send<T: Encodable & Sendable>(function: String?, response: BridgeResponse<T>) {
//         let encoder = JSONEncoder()
//         encoder.outputFormatting = .sortedKeys
//         guard let jsonData = try? encoder.encode(response),
//               let jsonString = String(data: jsonData, encoding: .utf8) else { return }
//         sendRawJS(function, jsonString)
//     }
// }
//
// ⚠️ 이 프로젝트에서 매크로를 사용하지 않는 이유:
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor (Swift 6) 환경에서는
// 매크로가 생성하는 코드가 @MainActor에 묶여버림.
// Effect.run { } 은 nonisolated 컨텍스트이므로 actor isolation 충돌 발생.
// → 매크로가 "못 만드는 게 아니라", actor isolation 문제 때문에 "못 쓰는 것"
// → 그래서 아래 수동 구현에서 nonisolated를 명시하여 우회

// ============================================================================
// MARK: - 수동 구현 버전 (이 프로젝트에서 실제 사용하는 형태)
// ============================================================================
//
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor 환경에서는
// 매크로가 생성하는 코드가 MainActor에 격리되어 Effect.run과 충돌.
// → 매크로 대신 직접 구현하고, nonisolated를 명시하여 우회.
//
// 매크로 대비 직접 작성해야 하는 부분:
// - struct 선언에 nonisolated 명시
// - DependencyKey conformance (liveValue / testValue) 직접 채택
// - DependencyValues extension 직접 작성
// - 모든 extension에 nonisolated 명시

/// MVVM의 `BridgeMessageSender` 프로토콜을 대체하는 TCA Dependency
/// - MVVM: protocol + class → TCA: struct + closure
/// - JS 콜백 함수에 응답을 전송하는 역할
nonisolated struct BridgeClient: Sendable {

    /// JS에 원시 문자열을 전송하는 클로저
    /// - function: JS 콜백 함수명 (예: "receiveUserInfo")
    /// - jsonString: JSON 인코딩된 응답 문자열
    ///
    /// MVVM에서는 BridgeHandler.sendToJS() 메서드가 이 역할을 했음
    /// TCA에서는 이 클로저를 통해 실제 BridgeHandler에게 위임
    var sendRawJS: @Sendable (_ function: String?, _ jsonString: String) -> Void
}

// MARK: - 편의 메서드

nonisolated extension BridgeClient {

    /// BridgeResponse<T>를 JSON으로 인코딩하여 JS에 전송
    /// - MVVM에서 BridgeHandler.sendToJS<T>(function:response:)에 해당
    /// - Reducer의 Effect 안에서 호출됨
    func send<T: Encodable & Sendable>(function: String?, response: BridgeResponse<T>) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let jsonData = try? encoder.encode(response),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        sendRawJS(function, jsonString)
    }
}

// MARK: - DependencyKey 등록

/// TCA의 의존성 시스템에 BridgeClient를 등록
/// - liveValue: 앱 실행 시 사용되는 기본값 (ViewController가 Store 생성 시 실제 구현으로 교체)
/// - testValue: 테스트 시 사용되는 기본값
///
nonisolated extension BridgeClient: DependencyKey {
    static let liveValue = BridgeClient(sendRawJS: { _, _ in })
    static let testValue = BridgeClient(sendRawJS: { _, _ in })
}

nonisolated extension DependencyValues {
    /// @Dependency(\.bridgeClient) 로 접근할 수 있도록 등록
    var bridgeClient: BridgeClient {
        get { self[BridgeClient.self] }
        set { self[BridgeClient.self] = newValue }
    }
}

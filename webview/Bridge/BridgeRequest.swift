//
//  BridgeRequest.swift
//  webview
//
//  Created by 차순혁 on 2/2/26.
//

import Foundation

// ============================================================================
// MARK: - Callback 기반 vs RPC 기반: 요청 구조 비교
// ============================================================================
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ Callback 기반 (기존 — feature/tca)                                      │
// │                                                                         │
// │ { type: "greeting", callback: "receiveMessage", data: { text: "Hi" } } │
// │                                                                         │
// │ - callback: JS 함수명 문자열 → Native가 evaluateJavaScript로 실행       │
// │ - 보안 리스크: 함수명 문자열 조립 → JS Injection 가능성                  │
// │ - 요청/응답 매칭 없음: 어떤 요청에 대한 응답인지 추적 불가                │
// ├─────────────────────────────────────────────────────────────────────────┤
// │ RPC 기반 (현재 — feature/secure-rpc)                                    │
// │                                                                         │
// │ { id: "uuid-1234", method: "greeting", params: { text: "Hi" } }        │
// │                                                                         │
// │ - id: 요청/응답 매칭용 고유 식별자 (JS pending map에서 resolve/reject)   │
// │ - method: BridgeMessageType enum과 1:1 매핑                             │
// │ - params: 기존 data와 동일 (AnyCodable로 보존)                          │
// │ - callback 함수명 제거 → 단일 엔트리포인트로 응답 (Injection 차단)       │
// └─────────────────────────────────────────────────────────────────────────┘

/// JS → Native RPC 요청의 공통 구조
/// - id: 요청/응답 매칭을 위한 고유 식별자 (JS에서 UUID 생성)
/// - method: BridgeMessageType enum으로 타입 안전한 메서드 디스패치
/// - params: AnyCodable로 보존 후, decodeParams()로 핸들러별 타입으로 디코딩
nonisolated struct BridgeRequest: Decodable, Sendable {
    let id: String
    let method: BridgeMessageType
    let params: AnyCodable?

    /// params 필드를 지정한 Decodable 타입으로 디코딩
    /// - 각 핸들러가 자신의 메시지에 맞는 타입을 지정하여 호출
    /// - 예: request.decodeParams(GreetingRequestData.self) → GreetingRequestData(text: "Hello")
    func decodeParams<T: Decodable>(_ type: T.Type) -> T? {
        guard let value = params?.value else { return nil }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: jsonData)
    }
}

// MARK: - 타입별 요청 데이터 모델

/// greeting 요청의 params 구조
nonisolated struct GreetingRequestData: Decodable, Sendable {
    let text: String
    let timestamp: String?
}

/// openUrl 요청의 params 구조
nonisolated struct OpenUrlRequestData: Decodable, Sendable {
    let url: String
}

/// showToast 요청의 params 구조
nonisolated struct ShowToastRequestData: Decodable, Sendable {
    let message: String
}

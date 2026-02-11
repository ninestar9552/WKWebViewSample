//
//  BridgeResponse.swift
//  webview
//
//  Created by 차순혁 on 2/2/26.
//

import Foundation

/// Native → JS 응답의 공통 구조 (제네릭)
/// - T에 핸들러별 Encodable 구조체를 지정하여 응답 데이터도 타입 안전하게 구성
/// - data가 필요 없는 에러 응답은 BridgeResponse(success:message:) 이니셜라이저 사용
/// - T에 Sendable 제약을 추가하여 BridgeResponse 자체도 Sendable로 보장
nonisolated struct BridgeResponse<T: Encodable & Sendable>: Encodable, Sendable {
    let success: Bool
    let message: String
    let data: T?
}

/// data 없이 success + message만으로 응답하는 경우 (에러 응답 등)
/// nonisolated: TCA의 Effect.run { } (nonisolated 컨텍스트)에서 호출되므로 명시 필요
nonisolated extension BridgeResponse where T == EmptyData {
    init(success: Bool, message: String) {
        self.success = success
        self.message = message
        self.data = nil
    }
}

/// data가 필요 없는 응답에 사용하는 빈 타입
nonisolated struct EmptyData: Encodable, Sendable {}

// MARK: - 타입별 응답 데이터 모델

/// greeting 응답의 data 구조
nonisolated struct GreetingResponseData: Encodable, Sendable {
    let text: String
}

/// getUserInfo 응답의 data 구조
nonisolated struct UserInfoResponseData: Encodable, Sendable {
    let name: String
    let device: String
    let osVersion: String
}

/// getAppVersion 응답의 data 구조
nonisolated struct AppVersionResponseData: Encodable, Sendable {
    let appVersion: String
    let osVersion: String
    let device: String
}

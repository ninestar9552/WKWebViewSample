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
struct BridgeResponse<T: Encodable>: Encodable {
    let success: Bool
    let message: String
    let data: T?
}

/// data 없이 success + message만으로 응답하는 경우 (에러 응답 등)
extension BridgeResponse where T == EmptyData {
    init(success: Bool, message: String) {
        self.success = success
        self.message = message
        self.data = nil
    }
}

/// data가 필요 없는 응답에 사용하는 빈 타입
struct EmptyData: Encodable {}

// MARK: - 타입별 응답 데이터 모델

/// greeting 응답의 data 구조
struct GreetingResponseData: Encodable {
    let text: String
}

/// getUserInfo 응답의 data 구조
struct UserInfoResponseData: Encodable {
    let name: String
    let device: String
    let osVersion: String
}

/// getAppVersion 응답의 data 구조
struct AppVersionResponseData: Encodable {
    let appVersion: String
    let osVersion: String
    let device: String
}

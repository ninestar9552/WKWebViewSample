//
//  BridgeRequest.swift
//  webview
//
//  Created by 차순혁 on 2/2/26.
//

import Foundation

/// JS → Native 메시지의 공통 구조
/// - JSONDecoder로 디코딩하여 type, callback은 바로 타입 매핑
/// - data는 AnyCodable로 보존 후, decodeData()로 핸들러별 타입으로 디코딩
struct BridgeRequest: Decodable {
    let type: BridgeMessageType
    let callback: String?
    let data: AnyCodable?

    /// data 필드를 지정한 Decodable 타입으로 디코딩
    /// - 각 핸들러가 자신의 메시지에 맞는 타입을 지정하여 호출
    /// - 예: request.decodeData(GreetingData.self) → GreetingData(text: "Hello")
    func decodeData<T: Decodable>(_ type: T.Type) -> T? {
        guard let value = data?.value else { return nil }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: jsonData)
    }
}

// MARK: - 타입별 요청 데이터 모델

/// greeting 요청의 data 구조
struct GreetingRequestData: Decodable {
    let text: String
    let timestamp: String?
}

/// openUrl 요청의 data 구조
struct OpenUrlRequestData: Decodable {
    let url: String
}

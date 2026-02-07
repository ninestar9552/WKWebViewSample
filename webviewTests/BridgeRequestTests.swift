//
//  BridgeRequestTests.swift
//  webviewTests
//
//  Created by 차순혁 on 2/7/26.
//

import Testing
import Foundation
@testable import webview

struct BridgeRequestTests {

    // MARK: - Helper

    /// JSON Dictionary → BridgeRequest 디코딩 헬퍼
    private func decode(_ dict: [String: Any]) -> BridgeRequest? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(BridgeRequest.self, from: data)
    }

    // MARK: - 기본 디코딩

    @Test func greeting_요청_디코딩() {
        let dict: [String: Any] = [
            "type": "greeting",
            "callback": "receiveMessageFromNative",
            "data": ["text": "Hello", "timestamp": "2026-02-07"]
        ]

        let request = decode(dict)
        #expect(request != nil)
        #expect(request?.type == .greeting)
        #expect(request?.callback == "receiveMessageFromNative")
    }

    @Test func openUrl_요청_디코딩() {
        let dict: [String: Any] = [
            "type": "openUrl",
            "callback": "receiveOpenUrlResponse",
            "data": ["url": "https://www.apple.com"]
        ]

        let request = decode(dict)
        #expect(request != nil)
        #expect(request?.type == .openUrl)
    }

    @Test func showToast_요청_디코딩() {
        let dict: [String: Any] = [
            "type": "showToast",
            "callback": "receiveToastResponse",
            "data": ["message": "저장되었습니다"]
        ]

        let request = decode(dict)
        #expect(request != nil)
        #expect(request?.type == .showToast)
    }

    @Test func callback_없는_요청_디코딩() {
        let dict: [String: Any] = [
            "type": "getUserInfo"
        ]

        let request = decode(dict)
        #expect(request != nil)
        #expect(request?.type == .getUserInfo)
        #expect(request?.callback == nil)
    }

    @Test func data_없는_요청_디코딩() {
        let dict: [String: Any] = [
            "type": "getAppVersion",
            "callback": "receiveAppVersion"
        ]

        let request = decode(dict)
        #expect(request != nil)
        #expect(request?.data == nil)
    }

    // MARK: - 실패 케이스

    @Test func 알수없는_type_디코딩_실패() {
        let dict: [String: Any] = [
            "type": "unknownType",
            "callback": "someCallback"
        ]

        let request = decode(dict)
        #expect(request == nil)
    }

    @Test func type_누락_시_디코딩_실패() {
        let dict: [String: Any] = [
            "callback": "someCallback",
            "data": ["text": "Hello"]
        ]

        let request = decode(dict)
        #expect(request == nil)
    }

    // MARK: - decodeData<T>

    @Test func decodeData_GreetingRequestData_성공() {
        let dict: [String: Any] = [
            "type": "greeting",
            "callback": "cb",
            "data": ["text": "Hello", "timestamp": "2026-02-07"]
        ]

        let request = decode(dict)
        let data = request?.decodeData(GreetingRequestData.self)
        #expect(data != nil)
        #expect(data?.text == "Hello")
        #expect(data?.timestamp == "2026-02-07")
    }

    @Test func decodeData_OpenUrlRequestData_성공() {
        let dict: [String: Any] = [
            "type": "openUrl",
            "callback": "cb",
            "data": ["url": "https://www.apple.com"]
        ]

        let request = decode(dict)
        let data = request?.decodeData(OpenUrlRequestData.self)
        #expect(data?.url == "https://www.apple.com")
    }

    @Test func decodeData_ShowToastRequestData_성공() {
        let dict: [String: Any] = [
            "type": "showToast",
            "callback": "cb",
            "data": ["message": "테스트"]
        ]

        let request = decode(dict)
        let data = request?.decodeData(ShowToastRequestData.self)
        #expect(data?.message == "테스트")
    }

    @Test func decodeData_타입_불일치_시_nil_반환() {
        let dict: [String: Any] = [
            "type": "greeting",
            "callback": "cb",
            "data": ["url": "https://example.com"]  // GreetingRequestData에는 text가 필요
        ]

        let request = decode(dict)
        let data = request?.decodeData(GreetingRequestData.self)
        #expect(data == nil)
    }

    @Test func decodeData_data가_nil일때_nil_반환() {
        let dict: [String: Any] = [
            "type": "getUserInfo",
            "callback": "cb"
        ]

        let request = decode(dict)
        let data = request?.decodeData(GreetingRequestData.self)
        #expect(data == nil)
    }

    @Test func decodeData_timestamp_생략_가능() {
        let dict: [String: Any] = [
            "type": "greeting",
            "callback": "cb",
            "data": ["text": "Hello"]  // timestamp 없음 (Optional)
        ]

        let request = decode(dict)
        let data = request?.decodeData(GreetingRequestData.self)
        #expect(data != nil)
        #expect(data?.text == "Hello")
        #expect(data?.timestamp == nil)
    }
}

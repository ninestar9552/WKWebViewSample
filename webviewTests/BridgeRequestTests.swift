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
            "id": "test-uuid",
            "method": "greeting",
            "params": ["text": "Hello", "timestamp": "2026-02-07"]
        ]

        let request = decode(dict)
        #expect(request != nil)
        #expect(request?.id == "test-uuid")
        #expect(request?.method == .greeting)
    }

    @Test func openUrl_요청_디코딩() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "openUrl",
            "params": ["url": "https://www.apple.com"]
        ]

        let request = decode(dict)
        #expect(request != nil)
        #expect(request?.method == .openUrl)
    }

    @Test func showToast_요청_디코딩() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "showToast",
            "params": ["message": "저장되었습니다"]
        ]

        let request = decode(dict)
        #expect(request != nil)
        #expect(request?.method == .showToast)
    }

    @Test func params_없는_요청_디코딩() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "getUserInfo"
        ]

        let request = decode(dict)
        #expect(request != nil)
        #expect(request?.method == .getUserInfo)
        #expect(request?.params == nil)
    }

    // MARK: - 실패 케이스

    @Test func 알수없는_method_디코딩_실패() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "unknownType"
        ]

        let request = decode(dict)
        #expect(request == nil)
    }

    @Test func method_누락_시_디코딩_실패() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "params": ["text": "Hello"]
        ]

        let request = decode(dict)
        #expect(request == nil)
    }

    @Test func id_누락_시_디코딩_실패() {
        let dict: [String: Any] = [
            "method": "greeting",
            "params": ["text": "Hello"]
        ]

        let request = decode(dict)
        #expect(request == nil)
    }

    // MARK: - decodeParams<T>

    @Test func decodeParams_GreetingRequestData_성공() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "greeting",
            "params": ["text": "Hello", "timestamp": "2026-02-07"]
        ]

        let request = decode(dict)
        let data = request?.decodeParams(GreetingRequestData.self)
        #expect(data != nil)
        #expect(data?.text == "Hello")
        #expect(data?.timestamp == "2026-02-07")
    }

    @Test func decodeParams_OpenUrlRequestData_성공() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "openUrl",
            "params": ["url": "https://www.apple.com"]
        ]

        let request = decode(dict)
        let data = request?.decodeParams(OpenUrlRequestData.self)
        #expect(data?.url == "https://www.apple.com")
    }

    @Test func decodeParams_ShowToastRequestData_성공() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "showToast",
            "params": ["message": "테스트"]
        ]

        let request = decode(dict)
        let data = request?.decodeParams(ShowToastRequestData.self)
        #expect(data?.message == "테스트")
    }

    @Test func decodeParams_타입_불일치_시_nil_반환() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "greeting",
            "params": ["url": "https://example.com"]  // GreetingRequestData에는 text가 필요
        ]

        let request = decode(dict)
        let data = request?.decodeParams(GreetingRequestData.self)
        #expect(data == nil)
    }

    @Test func decodeParams_params가_nil일때_nil_반환() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "getUserInfo"
        ]

        let request = decode(dict)
        let data = request?.decodeParams(GreetingRequestData.self)
        #expect(data == nil)
    }

    @Test func decodeParams_timestamp_생략_가능() {
        let dict: [String: Any] = [
            "id": "test-uuid",
            "method": "greeting",
            "params": ["text": "Hello"]  // timestamp 없음 (Optional)
        ]

        let request = decode(dict)
        let data = request?.decodeParams(GreetingRequestData.self)
        #expect(data != nil)
        #expect(data?.text == "Hello")
        #expect(data?.timestamp == nil)
    }
}

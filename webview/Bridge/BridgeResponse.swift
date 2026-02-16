//
//  BridgeResponse.swift
//  webview
//
//  Created by 차순혁 on 2/2/26.
//

import Foundation

// ============================================================================
// MARK: - Callback 기반 vs RPC 기반: 응답 구조 비교
// ============================================================================
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ Callback 기반 (기존 — feature/tca)                                      │
// │                                                                         │
// │ Native: evaluateJavaScript("receiveMessage({success:true,...})")        │
// │                                                                         │
// │ { success: true, message: "성공", data: { text: "Hello" } }            │
// │                                                                         │
// │ - 응답에 요청 id가 없음 → 어떤 요청의 응답인지 매칭 불가                 │
// │ - callback 함수명으로 응답 전달 → 함수별로 JS 핸들러 분산                │
// │ - success/message로 성공/실패 표현                                       │
// ├─────────────────────────────────────────────────────────────────────────┤
// │ RPC 기반 (현재 — feature/secure-rpc)                                    │
// │                                                                         │
// │ Native: callAsyncJavaScript("window.__bridgeResolve(response)", ...)   │
// │                                                                         │
// │ 성공: { id: "uuid-1234", result: { text: "Hello" } }                   │
// │ 실패: { id: "uuid-1234", error: { code: "INVALID_PARAMS",             │
// │        message: "파싱 실패" } }                                        │
// │                                                                         │
// │ - id로 요청/응답 매칭 → JS pending map에서 resolve/reject               │
// │ - 단일 엔트리포인트(__bridgeResolve)로 모든 응답 수신                    │
// │ - result/error 분리 → 성공과 실패가 구조적으로 구분됨                    │
// └─────────────────────────────────────────────────────────────────────────┘

/// Native → JS RPC 응답의 공통 구조 (제네릭)
/// - id: 요청과 매칭되는 고유 식별자
/// - result: 성공 시 응답 데이터 (T: Encodable & Sendable)
/// - error: 실패 시 에러 정보
/// - result과 error는 상호 배타적: 성공이면 result만, 실패면 error만 존재
nonisolated struct BridgeResponse<T: Encodable & Sendable>: Encodable, Sendable {
    let id: String
    let result: T?
    let error: BridgeError?
}

// MARK: - 에러 코드 (계약)

/// JS/Native 양쪽에서 분기 처리에 사용하는 에러 코드
/// - RawValue가 그대로 JSON의 code 필드로 인코딩됨
/// - 새 에러 코드 추가 시 JS 쪽 핸들링도 함께 업데이트 필요
nonisolated enum BridgeErrorCode: String, Encodable, Sendable {
    case invalidParams    = "INVALID_PARAMS"       // params 디코딩 실패 / 필수 필드 누락
    case methodNotAllowed = "METHOD_NOT_ALLOWED"   // 미등록 method 호출
    case parseError       = "PARSE_ERROR"          // 요청 JSON 파싱 자체 실패
    case unauthorized     = "UNAUTHORIZED"         // 인증 필요
    case internalError    = "INTERNAL_ERROR"       // Native 내부 오류
    case timeout          = "TIMEOUT"              // 요청 처리 시간 초과
}

/// 에러 코드별 기본 메시지 템플릿
/// - 호출부에서 상세 메시지를 따로 지정하지 않을 때 사용
nonisolated extension BridgeErrorCode {
    var defaultMessage: String {
        switch self {
        case .invalidParams:    return "요청 값이 올바르지 않습니다."
        case .methodNotAllowed: return "허용되지 않은 요청입니다."
        case .parseError:       return "요청을 처리할 수 없습니다."
        case .unauthorized:     return "인증이 필요합니다."
        case .internalError:    return "일시적인 오류가 발생했습니다."
        case .timeout:          return "요청 시간이 초과되었습니다."
        }
    }
}

/// RPC 에러 정보
/// - code: BridgeErrorCode enum (JS 분기용 — 안정적 계약)
/// - message: 사용자/개발자용 문구 (상황별 동적 생성 가능)
nonisolated struct BridgeError: Encodable, Sendable {
    let code: BridgeErrorCode
    let message: String
}

/// 성공 응답 편의 이니셜라이저
nonisolated extension BridgeResponse {
    init(id: String, result: T) {
        self.id = id
        self.result = result
        self.error = nil
    }
}

/// 에러 응답 편의 이니셜라이저 (result 데이터 없음)
/// - message 생략 시 BridgeErrorCode.defaultMessage 사용
nonisolated extension BridgeResponse where T == EmptyData {
    init(id: String, code: BridgeErrorCode, message: String? = nil) {
        self.id = id
        self.result = nil
        self.error = BridgeError(code: code, message: message ?? code.defaultMessage)
    }
}

/// result 데이터가 필요 없는 응답에서 제네릭 T를 채우기 위한 빈 타입
/// - 에러 응답: BridgeResponse<EmptyData>(id:code:message:) → result = nil
/// - 성공이지만 데이터 없음: BridgeResponse(id:result: EmptyData()) → result = {}
nonisolated struct EmptyData: Encodable, Sendable {}

// MARK: - 타입별 응답 데이터 모델

/// greeting 응답의 result 구조
nonisolated struct GreetingResponseData: Encodable, Sendable {
    let text: String
}

/// getUserInfo 응답의 result 구조
nonisolated struct UserInfoResponseData: Encodable, Sendable {
    let name: String
    let device: String
    let osVersion: String
}

/// getAppVersion 응답의 result 구조
nonisolated struct AppVersionResponseData: Encodable, Sendable {
    let appVersion: String
    let osVersion: String
    let device: String
}

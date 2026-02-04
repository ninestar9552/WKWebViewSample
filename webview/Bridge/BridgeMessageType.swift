//
//  BridgeMessageType.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import Foundation

/// JS → Native 메시지의 type 필드를 enum으로 관리
/// - 문자열 비교 대신 enum을 사용하여 오타 방지 및 컴파일 타임 안전성 확보
/// - 새로운 메시지 타입 추가 시 switch문에서 누락을 컴파일러가 잡아줌
/// - RawValue를 String으로 설정하여 JS에서 전달하는 문자열과 1:1 매핑
enum BridgeMessageType: String, Codable {
    case greeting       // 인사 메시지 전송
    case getUserInfo    // 디바이스 사용자 정보 요청
    case getAppVersion  // 앱 버전 정보 요청
    case openUrl        // 새 화면에서 URL 열기 (navigation push)
    case showToast      // 토스트 메시지 표시
}

//
//  SecurityConfig.swift
//  webview
//
//  Created by 차순혁 on 2/2/26.
//

import Foundation

/// WebView 보안 정책을 한 곳에서 관리하는 설정
/// - URL 네비게이션 화이트리스트와 Bridge 통신 허용 도메인을 분리하여 관리
/// - 새로운 도메인 추가 시 이 파일만 수정하면 됨
enum SecurityConfig {

    // MARK: - Navigation Whitelist

    /// WebView 내에서 이동을 허용하는 도메인 목록
    /// - 이 목록에 없는 도메인으로의 네비게이션은 차단됨
    /// - 서브도메인도 허용 (예: "apple.com" → "www.apple.com", "support.apple.com" 모두 허용)
    static let allowedDomains: [String] = [
        "apple.com",
        "google.com",
    ]

    /// file:// 스킴 허용 여부 (로컬 HTML 로딩용)
    static let allowFileScheme = true

    // MARK: - Bridge Security

    /// JS Bridge postMessage를 허용하는 출처 목록
    /// - 이 목록에 없는 출처에서 보낸 Bridge 메시지는 무시됨
    /// - "file://" : 로컬 HTML에서의 Bridge 호출 허용
    /// - 원격 페이지에서 Bridge를 사용해야 하는 경우 해당 도메인을 추가
    ///   (예: "myservice.com" → https://www.myservice.com 에서 로드된 웹페이지도 Bridge 호출 가능)
    static let trustedBridgeOrigins: [String] = [
        "file://",
        "myservice.com",
    ]

    // MARK: - Validation

    /// 주어진 URL의 호스트가 화이트리스트에 포함되는지 검사
    /// - 서브도메인 매칭을 지원 (예: "www.apple.com"은 "apple.com"에 매칭)
    /// - host가 nil인 경우 (file:// 등) false 반환
    static func isDomainAllowed(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return allowedDomains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }

    /// 주어진 URL이 신뢰할 수 있는 Bridge 출처인지 검사
    /// - file:// 스킴이거나 trustedBridgeOrigins에 등록된 도메인이면 허용
    static func isTrustedBridgeOrigin(_ url: URL?) -> Bool {
        guard let url = url else { return false }

        if url.scheme == "file" {
            return trustedBridgeOrigins.contains("file://")
        }

        guard let host = url.host?.lowercased() else { return false }
        return trustedBridgeOrigins.contains { origin in
            host == origin || host.hasSuffix(".\(origin)")
        }
    }
}

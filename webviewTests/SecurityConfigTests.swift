//
//  SecurityConfigTests.swift
//  webviewTests
//
//  Created by 차순혁 on 2/7/26.
//

import Testing
import Foundation
@testable import webview

struct SecurityConfigTests {

    // MARK: - isDomainAllowed

    @Test func isDomainAllowed_정확한_도메인_매칭() {
        #expect(SecurityConfig.isDomainAllowed("apple.com") == true)
        #expect(SecurityConfig.isDomainAllowed("google.com") == true)
    }

    @Test func isDomainAllowed_서브도메인_매칭() {
        #expect(SecurityConfig.isDomainAllowed("www.apple.com") == true)
        #expect(SecurityConfig.isDomainAllowed("support.apple.com") == true)
        #expect(SecurityConfig.isDomainAllowed("maps.google.com") == true)
    }

    @Test func isDomainAllowed_미등록_도메인_차단() {
        #expect(SecurityConfig.isDomainAllowed("evil.com") == false)
        #expect(SecurityConfig.isDomainAllowed("naver.com") == false)
    }

    @Test func isDomainAllowed_nil_호스트_처리() {
        #expect(SecurityConfig.isDomainAllowed(nil) == false)
    }

    @Test func isDomainAllowed_대소문자_무시() {
        #expect(SecurityConfig.isDomainAllowed("APPLE.COM") == true)
        #expect(SecurityConfig.isDomainAllowed("Apple.Com") == true)
    }

    @Test func isDomainAllowed_유사_도메인_차단() {
        // "apple.com"을 허용하더라도 "notapple.com"은 차단
        #expect(SecurityConfig.isDomainAllowed("notapple.com") == false)
        #expect(SecurityConfig.isDomainAllowed("fakeapple.com") == false)
    }

    // MARK: - isTrustedBridgeOrigin

    @Test func isTrustedBridgeOrigin_file_스킴_허용() {
        let fileURL = URL(string: "file:///path/to/index.html")
        #expect(SecurityConfig.isTrustedBridgeOrigin(fileURL) == true)
    }

    @Test func isTrustedBridgeOrigin_등록된_도메인_허용() {
        let url = URL(string: "https://www.myservice.com/page")
        #expect(SecurityConfig.isTrustedBridgeOrigin(url) == true)

        let subdomainURL = URL(string: "https://api.myservice.com/bridge")
        #expect(SecurityConfig.isTrustedBridgeOrigin(subdomainURL) == true)
    }

    @Test func isTrustedBridgeOrigin_미등록_도메인_차단() {
        let url = URL(string: "https://evil.com/inject")
        #expect(SecurityConfig.isTrustedBridgeOrigin(url) == false)

        let anotherURL = URL(string: "https://www.apple.com")
        #expect(SecurityConfig.isTrustedBridgeOrigin(anotherURL) == false)
    }

    @Test func isTrustedBridgeOrigin_nil_URL_처리() {
        #expect(SecurityConfig.isTrustedBridgeOrigin(nil) == false)
    }
}

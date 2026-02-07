//
//  BridgeHandlerTests.swift
//  webviewTests
//
//  Created by 차순혁 on 2/7/26.
//

import Testing
@testable import webview

struct BridgeHandlerTests {

    let handler = BridgeHandler()

    // MARK: - 유효한 함수명

    @Test func validName_일반_영문() {
        #expect(handler.isValidJSFunctionName("callback"))
    }

    @Test func validName_camelCase() {
        #expect(handler.isValidJSFunctionName("receiveUserInfo"))
    }

    @Test func validName_dot_구분자() {
        #expect(handler.isValidJSFunctionName("window.callback"))
    }

    @Test func validName_underscore_시작() {
        #expect(handler.isValidJSFunctionName("_private"))
    }

    @Test func validName_dollar_시작() {
        #expect(handler.isValidJSFunctionName("$handler"))
    }

    @Test func validName_숫자_포함() {
        #expect(handler.isValidJSFunctionName("handler2"))
    }

    // MARK: - JS Injection 차단

    @Test func invalidName_세미콜론_injection() {
        #expect(!handler.isValidJSFunctionName("alert();void"))
    }

    @Test func invalidName_괄호_injection() {
        #expect(!handler.isValidJSFunctionName("alert(1)"))
    }

    @Test func invalidName_공백_포함() {
        #expect(!handler.isValidJSFunctionName("func name"))
    }

    @Test func invalidName_빈_문자열() {
        #expect(!handler.isValidJSFunctionName(""))
    }

    @Test func invalidName_숫자_시작() {
        #expect(!handler.isValidJSFunctionName("1callback"))
    }

    @Test func invalidName_줄바꿈_포함() {
        #expect(!handler.isValidJSFunctionName("a\nb"))
    }

    @Test func invalidName_중괄호_포함() {
        #expect(!handler.isValidJSFunctionName("a{b}"))
    }

    @Test func invalidName_대입연산자_포함() {
        #expect(!handler.isValidJSFunctionName("a=1"))
    }

    @Test func invalidName_백틱_templateLiteral() {
        #expect(!handler.isValidJSFunctionName("a`b`"))
    }

    @Test func invalidName_따옴표_포함() {
        #expect(!handler.isValidJSFunctionName("a'b"))
    }
}

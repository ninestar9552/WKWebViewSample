/**
 * Native Bridge Communication Module
 * WKWebView와 Native 간 통신을 위한 JavaScript 모듈
 */

// ============================================
// JS → Native 통신
// ============================================

/**
 * Native에 메시지를 전송합니다.
 * WKScriptMessageHandler를 통해 Native로 메시지 전달
 */
function sendMessageToNative() {
    const message = {
        type: "greeting",
        data: {
            text: "Hello from JavaScript!",
            timestamp: new Date().toISOString()
        }
    };

    // WKWebView의 messageHandler를 통해 Native로 전송
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeBridge) {
        window.webkit.messageHandlers.nativeBridge.postMessage(message);
        appendMessage("[JS → Native] 메시지 전송: " + message.data.text);
    } else {
        appendMessage("[오류] Native Bridge를 사용할 수 없습니다.");
    }
}

/**
 * Native에 데이터를 요청합니다.
 */
function requestDataFromNative() {
    const request = {
        type: "request",
        data: {
            action: "getUserInfo",
            timestamp: new Date().toISOString()
        }
    };

    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeBridge) {
        window.webkit.messageHandlers.nativeBridge.postMessage(request);
        appendMessage("[JS → Native] 데이터 요청: " + request.data.action);
    } else {
        appendMessage("[오류] Native Bridge를 사용할 수 없습니다.");
    }
}

// ============================================
// Native → JS 통신
// ============================================

/**
 * Native에서 호출하는 함수
 * @param {Object} data - Native에서 전달받은 데이터
 */
function receiveMessageFromNative(data) {
    appendMessage("[Native → JS] 수신: " + JSON.stringify(data));
}

/**
 * Native에서 사용자 정보를 전달받는 함수
 * @param {Object} userInfo - 사용자 정보 객체
 */
function receiveUserInfo(userInfo) {
    appendMessage("[Native → JS] 사용자 정보 수신:");
    appendMessage("  - 이름: " + userInfo.name);
    appendMessage("  - 디바이스: " + userInfo.device);
    appendMessage("  - OS 버전: " + userInfo.osVersion);
}

// ============================================
// UI 업데이트
// ============================================

/**
 * 메시지 박스에 메시지를 추가합니다.
 * @param {string} message - 표시할 메시지
 */
function appendMessage(message) {
    const messageBox = document.getElementById("messageBox");
    const timestamp = new Date().toLocaleTimeString("ko-KR");
    messageBox.innerHTML += "[" + timestamp + "] " + message + "<br>";
    messageBox.scrollTop = messageBox.scrollHeight;
}

/**
 * 메시지 박스를 초기화합니다.
 */
function clearMessages() {
    const messageBox = document.getElementById("messageBox");
    messageBox.innerHTML = "";
}

// 페이지 로드 완료 시 초기화
document.addEventListener("DOMContentLoaded", function() {
    appendMessage("Bridge 초기화 완료");
});

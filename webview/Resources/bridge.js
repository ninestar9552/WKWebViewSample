/**
 * Native Bridge Communication Module
 * WKWebView와 Native 간 통신을 위한 JavaScript 모듈
 */

// ============================================
// JS → Native 통신
// ============================================

/**
 * Native Bridge로 메시지를 전송하는 공통 함수
 * @param {Object} message - 전송할 메시지 객체 { type, callback, data }
 * @param {string} logMessage - 로그에 표시할 메시지
 */
function postToNative(message, logMessage) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeBridge) {
        window.webkit.messageHandlers.nativeBridge.postMessage(message);
        appendMessage("[요청][JS → Native]\n" + logMessage);
    } else {
        appendMessage("[오류] Native Bridge를 사용할 수 없습니다.");
    }
}

/**
 * Native에 메시지를 전송합니다.
 */
function sendMessageToNative() {
    postToNative({
        type: "greeting",
        callback: "receiveMessageFromNative",
        data: {
            text: "Hello from JavaScript!",
            timestamp: new Date().toISOString()
        }
    }, "메시지 전송: Hello from JavaScript!");
}

/**
 * Native에 데이터를 요청합니다.
 */
function requestDataFromNative() {
    postToNative({
        type: "getUserInfo",
        callback: "receiveUserInfo",
        data: {}
    }, "데이터 요청: getUserInfo");
}

// ============================================
// Native → JS 통신
// ============================================

/**
 * Native에서 호출하는 함수
 * @param {Object} data - Native에서 전달받은 데이터
 */
function receiveMessageFromNative(data) {
    appendMessage("[수신][Native → JS]\n" + data.message);
}

/**
 * Native에서 사용자 정보를 전달받는 함수
 * @param {Object} userInfo - 사용자 정보 객체
 */
function receiveUserInfo(userInfo) {
    appendMessage("[수신][Native → JS] 사용자 정보");
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
    const formatted = message.replace(/\n/g, "<br>");
    messageBox.innerHTML += "[" + timestamp + "] " + formatted + "<br>";
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

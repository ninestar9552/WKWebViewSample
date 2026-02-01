/**
 * Native Bridge Communication Module
 * WKWebView와 Native 간 양방향 통신을 위한 JavaScript 모듈
 *
 * [요청] JS → Native 메시지 구조: { type, callback, data }
 * - type: 메시지 종류 (Native의 BridgeMessageType enum과 1:1 매핑)
 * - callback: Native가 응답 시 호출할 JS 함수명
 * - data: 전달할 데이터 객체
 *
 * [응답] Native → JS 응답 규격: { success, message, data }
 * - success: 요청 처리 성공/실패 여부
 * - message: 사용자에게 표시할 수 있는 안내 메시지 (팝업, 토스트 등)
 * - data: 응답 데이터 (성공/실패 모두 포함 가능)
 */

// ============================================
// JS → Native 통신
// ============================================

/**
 * Native Bridge로 메시지를 전송하는 공통 함수
 * - postMessage 호출 전 Bridge 존재 여부를 확인하여 안전하게 전송
 * - 모든 JS → Native 전송이 이 함수를 거치도록 통일하여 중복 코드 제거
 * @param {Object} message - 전송할 메시지 객체 { type, callback, data }
 * @param {string} logMessage - 화면에 표시할 로그 메시지
 */
function postToNative(message, logMessage) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeBridge) {
        window.webkit.messageHandlers.nativeBridge.postMessage(message);
        appendMessage("request", "JS → Native", logMessage);
    } else {
        appendMessage("error", "", "Native Bridge를 사용할 수 없습니다.");
    }
}

/**
 * Native에 인사 메시지를 전송합니다.
 * - callback으로 "receiveMessageFromNative"를 지정하여 Native가 응답할 함수를 알려줌
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
 * Native에 사용자 정보를 요청합니다.
 * - callback으로 "receiveUserInfo"를 지정하여 Native가 해당 함수로 데이터를 전달
 */
function requestDataFromNative() {
    postToNative({
        type: "getUserInfo",
        callback: "receiveUserInfo",
        data: {}
    }, "데이터 요청: getUserInfo");
}

// ============================================
// Navigation 테스트
// ============================================

/**
 * URL 입력칸의 주소로 WebView를 이동시켜 프로그레스바 동작을 테스트
 * - 실제 웹페이지 로딩으로 KVO estimatedProgress 변화를 확인
 */
function navigateToUrl() {
    var url = document.getElementById("urlInput").value.trim();
    if (!url) {
        appendMessage("error", "", "URL을 입력해주세요.");
        return;
    }
    if (!url.startsWith("http")) {
        url = "https://" + url;
    }
    appendMessage("info", "", "페이지 이동: " + url);
    window.location.href = url;
}

/**
 * 존재하지 않는 URL로 이동하여 NavigationDelegate의 에러 처리를 테스트
 * - didFailProvisionalNavigation이 호출되어 에러 알럿이 표시되어야 함
 */
function navigateToInvalidUrl() {
    appendMessage("info", "", "에러 테스트: 존재하지 않는 도메인으로 이동");
    window.location.href = "https://this-domain-does-not-exist-12345.com";
}

/**
 * Native에 정의되지 않은 메시지 타입을 전송하여 에러 응답을 테스트
 * - BridgeMessageType enum에 없는 타입이므로 "요청을 처리할 수 없습니다" 응답이 와야 함
 */
function triggerUnknownBridgeMessage() {
    postToNative({
        type: "unknownType",
        callback: "receiveErrorResponse",
        data: {}
    }, "에러 테스트: 알 수 없는 메시지 타입 전송");
}

/**
 * 알 수 없는 메시지 타입에 대한 Native 에러 응답 수신
 */
function receiveErrorResponse(response) {
    if (response.success) {
        appendMessage("success", "Native → JS", response.message);
    } else {
        appendMessage("fail", "Native → JS", response.message);
    }
}

// ============================================
// Native → JS 통신 (콜백 함수)
// Native가 evaluateJavaScript로 호출하는 함수들
// ============================================

/**
 * greeting 요청에 대한 Native의 응답을 수신
 * @param {Object} response - { success, message, data }
 */
function receiveMessageFromNative(response) {
    if (response.success) {
        appendMessage("success", "Native → JS", response.message + "\n" + response.data.text);
    } else {
        appendMessage("fail", "Native → JS", response.message);
    }
}

/**
 * getUserInfo 요청에 대한 Native의 응답을 수신
 * @param {Object} response - { success, message, data }
 */
function receiveUserInfo(response) {
    if (response.success) {
        var body = response.message
            + "\n이름: " + response.data.name
            + "\n디바이스: " + response.data.device
            + "\nOS: " + response.data.osVersion;
        appendMessage("success", "Native → JS", body);
    } else {
        appendMessage("fail", "Native → JS", response.message);
    }
}

// ============================================
// UI 업데이트
// ============================================

/**
 * 메시지 박스에 로그 스타일로 메시지를 추가
 * - tag별 색상으로 요청/성공/실패/정보를 시각적으로 구분
 * - 24시간 형식 타임스탬프 (HH:MM:SS)
 * - 새 메시지 추가 후 자동 스크롤
 * @param {string} tag - 메시지 유형 (request, success, fail, info, error)
 * @param {string} direction - 통신 방향 (예: "JS → Native")
 * @param {string} body - 메시지 내용
 */
function appendMessage(tag, direction, body) {
    const messageBox = document.getElementById("messageBox");

    // 24시간 형식 타임스탬프
    const now = new Date();
    const timestamp = [now.getHours(), now.getMinutes(), now.getSeconds()]
        .map(function(n) { return n < 10 ? "0" + n : n; })
        .join(":");

    // 태그 라벨 매핑
    var tagLabels = {
        request: "요청", success: "수신", fail: "실패", info: "정보", error: "오류"
    };
    var tagLabel = tagLabels[tag] || tag;

    // \n을 <br>로 변환
    var formattedBody = body.replace(/\n/g, "<br>");

    // 방향 표시 (비어있으면 생략)
    var directionHtml = direction
        ? '<span class="log-direction">' + direction + '</span>'
        : '';

    var html = '<div class="log-entry">'
        + '<span class="log-time">' + timestamp + '</span>'
        + '<span class="log-tag tag-' + tag + '">' + tagLabel + '</span>'
        + directionHtml
        + '<div class="log-body">' + formattedBody + '</div>'
        + '</div>';

    messageBox.innerHTML += html;
    messageBox.scrollTop = messageBox.scrollHeight;
}

/**
 * 메시지 박스를 초기화합니다.
 */
function clearMessages() {
    const messageBox = document.getElementById("messageBox");
    messageBox.innerHTML = "";
}

// 페이지 로드 완료 시 Bridge 초기화 상태를 표시
document.addEventListener("DOMContentLoaded", function() {
    appendMessage("info", "", "Bridge 초기화 완료");
});

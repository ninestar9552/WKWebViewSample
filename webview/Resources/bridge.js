/**
 * Native Bridge Communication Module
 * WKWebView와 Native 간 양방향 통신을 위한 JavaScript 모듈
 *
 * ┌─────────────────────────────────────────────────────────────────────┐
 * │ Callback 기반 (기존 — feature/tca)                                  │
 * │                                                                     │
 * │ [요청] JS → Native: { type, callback, data }                        │
 * │ [응답] Native → JS: evaluateJavaScript("callback({success,...})")   │
 * │                                                                     │
 * │ - 함수별로 콜백이 분산 (receiveUserInfo, receiveAppVersion, ...)     │
 * │ - callback 함수명이 JS Injection 벡터                               │
 * │ - 요청/응답 매칭 불가 (어떤 요청의 응답인지 추적 불가)               │
 * ├─────────────────────────────────────────────────────────────────────┤
 * │ RPC 기반 (현재 — feature/secure-rpc)                                │
 * │                                                                     │
 * │ [요청] JS → Native: { id, method, params }                          │
 * │ [응답] Native → JS: window.__bridgeResolve({ id, result/error })    │
 * │                                                                     │
 * │ - callNative()가 Promise를 반환 → async/await로 사용                │
 * │ - pending map으로 id 기반 요청/응답 매칭                             │
 * │ - 단일 엔트리포인트(__bridgeResolve)로 모든 응답 수신                │
 * │ - callback 함수명 제거 → JS Injection 차단                          │
 * └─────────────────────────────────────────────────────────────────────┘
 */

// ============================================
// RPC 인프라
// ============================================

/** 요청/응답 매칭을 위한 pending map — { id: { resolve, reject } } */
var _pendingRequests = {};

/**
 * UUID v4 생성
 * - crypto.randomUUID() 우선 사용 (iOS 15.4+)
 * - 미지원 환경 폴백
 */
function _generateUUID() {
    if (typeof crypto !== "undefined" && crypto.randomUUID) {
        return crypto.randomUUID();
    }
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
        var r = (Math.random() * 16) | 0;
        var v = c === "x" ? r : (r & 0x3) | 0x8;
        return v.toString(16);
    });
}

/**
 * Native → JS 응답 수신 단일 엔트리포인트
 * - Native가 window.__bridgeResolve(response)를 호출
 * - response: { id, result } (성공) 또는 { id, error: { code, message } } (실패)
 * - pending map에서 id로 해당 Promise를 찾아 resolve/reject
 */
window.__bridgeResolve = function (response) {
    var id = response.id;
    var pending = _pendingRequests[id];

    if (!pending) {
        console.warn("[Bridge] 매칭되지 않는 응답 id:", id);
        return;
    }

    delete _pendingRequests[id];

    if (response.error) {
        pending.reject(response.error);
    } else {
        pending.resolve(response.result);
    }
};

/**
 * JS → Native RPC 호출 (Promise 반환)
 *
 * Callback 기반: postToNative({ type, callback, data })  → void (응답은 콜백 함수로)
 * RPC 기반:     callNative(method, params)                → Promise (응답은 resolve/reject로)
 *
 * @param {string} method - BridgeMessageType enum과 1:1 매핑
 * @param {Object} [params] - 요청 파라미터
 * @returns {Promise} 성공 시 result 객체, 실패 시 { code, message } 에러
 */
function callNative(method, params) {
    return new Promise(function (resolve, reject) {
        if (
            !window.webkit ||
            !window.webkit.messageHandlers ||
            !window.webkit.messageHandlers.nativeBridge
        ) {
            reject({
                code: "INTERNAL_ERROR",
                message: "Native Bridge를 사용할 수 없습니다.",
            });
            return;
        }

        var id = _generateUUID();
        _pendingRequests[id] = { resolve: resolve, reject: reject };

        window.webkit.messageHandlers.nativeBridge.postMessage({
            id: id,
            method: method,
            params: params || {},
        });
    });
}

// ============================================
// JS → Native 통신
// ============================================

/**
 * Native에 인사 메시지를 전송합니다.
 *
 * Callback 기반: postToNative({ type: "greeting", callback: "receiveMessageFromNative", data: {...} })
 * RPC 기반:     callNative("greeting", {...}).then(result => ...)
 */
async function sendMessageToNative() {
    appendMessage("request", "JS → Native", "메시지 전송: Hello from JavaScript!");
    try {
        var result = await callNative("greeting", {
            text: "Hello from JavaScript!",
            timestamp: new Date().toISOString(),
        });
        appendMessage("success", "Native → JS", result.text);
    } catch (error) {
        appendMessage("fail", "Native → JS", error.message);
    }
}

/**
 * Native에 사용자 정보를 요청합니다.
 */
async function requestDataFromNative() {
    appendMessage("request", "JS → Native", "데이터 요청: getUserInfo");
    try {
        var result = await callNative("getUserInfo");
        var body =
            "이름: " + result.name +
            "\n디바이스: " + result.device +
            "\nOS: " + result.osVersion;
        appendMessage("success", "Native → JS", body);
    } catch (error) {
        appendMessage("fail", "Native → JS", error.message);
    }
}

/**
 * Native에 앱 버전 정보를 요청합니다.
 */
async function requestAppVersion() {
    appendMessage("request", "JS → Native", "데이터 요청: getAppVersion");
    try {
        var result = await callNative("getAppVersion");
        var body =
            "앱 버전: " + result.appVersion +
            "\nOS: " + result.osVersion +
            "\n디바이스: " + result.device;
        appendMessage("success", "Native → JS", body);
    } catch (error) {
        appendMessage("fail", "Native → JS", error.message);
    }
}

/**
 * Native에 토스트 메시지 표시를 요청합니다.
 */
async function showNativeToast() {
    appendMessage("request", "JS → Native", "토스트 표시 요청");
    try {
        await callNative("showToast", {
            message: "안녕하세요! Native 토스트입니다.",
        });
        appendMessage("success", "Native → JS", "토스트 표시 완료");
    } catch (error) {
        appendMessage("fail", "Native → JS", error.message);
    }
}

// ============================================
// Navigation 테스트
// ============================================

/**
 * URL 입력칸의 주소로 WebView를 이동시켜 프로그레스바 동작을 테스트
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
 */
function navigateToInvalidUrl() {
    appendMessage("info", "", "에러 테스트: 존재하지 않는 도메인으로 이동");
    window.location.href = "https://this-does-not-exist-12345.apple.com";
}

/**
 * 화이트리스트에 없는 도메인으로 이동하여 차단되는지 테스트
 */
function navigateToBlockedDomain() {
    appendMessage("info", "", "보안 테스트: 화이트리스트 미등록 도메인으로 이동");
    window.location.href = "https://www.example.com";
}

/**
 * HTTP 404 응답을 반환하는 URL로 이동하여 navigationResponse 에러 처리를 테스트
 */
function navigateToHttp404() {
    appendMessage("info", "", "에러 테스트: HTTP 404 응답");
    window.location.href =
        "https://www.apple.com/this-page-does-not-exist-404-test";
}

/**
 * Native에 정의되지 않은 메시지 타입을 전송하여 에러 응답을 테스트
 * - BridgeMessageType enum에 없는 method → PARSE_ERROR 응답
 */
async function triggerUnknownBridgeMessage() {
    appendMessage(
        "request",
        "JS → Native",
        "에러 테스트: 알 수 없는 메시지 타입 전송"
    );
    try {
        await callNative("unknownType");
        appendMessage("success", "Native → JS", "(예상치 못한 성공)");
    } catch (error) {
        appendMessage(
            "fail",
            "Native → JS",
            "[" + error.code + "] " + error.message
        );
    }
}

// ============================================
// JS Dialog 테스트 (WKUIDelegate)
// ============================================

function testAlert() {
    appendMessage("info", "", "alert() 호출");
    alert(
        "이것은 JS alert() 입니다.\nWKUIDelegate가 네이티브 알럿으로 변환합니다."
    );
}

function testConfirm() {
    appendMessage("info", "", "confirm() 호출");
    var result = confirm("확인 또는 취소를 선택하세요.");
    appendMessage("success", "", "confirm 결과: " + result);
}

function testPrompt() {
    appendMessage("info", "", "prompt() 호출");
    var input = prompt("이름을 입력하세요:", "차순혁");
    appendMessage(
        "success",
        "",
        "prompt 입력값: " + (input !== null ? input : "(취소됨)")
    );
}

// ============================================
// 새 창/탭 열기 테스트
// ============================================

/**
 * window.open()으로 새 창을 열어 createWebViewWith 동작을 테스트
 */
function openPopupWindow() {
    appendMessage("info", "", "window.open() 호출 (모달)");
    window.open("https://www.apple.com", "_blank");
}

/**
 * Bridge openUrl로 새 탭(네비게이션 push)에서 URL 열기
 */
async function openUrlInNewTab() {
    appendMessage("request", "JS → Native", "새 탭에서 URL 열기 (push)");
    try {
        await callNative("openUrl", { url: "https://www.apple.com" });
        appendMessage("success", "Native → JS", "URL 열기 완료");
    } catch (error) {
        appendMessage("fail", "Native → JS", error.message);
    }
}

// ============================================
// 환경 정보
// ============================================

function showUserAgent() {
    appendMessage("info", "", "User-Agent:\n" + navigator.userAgent);
}

// ============================================
// URL 스킴 테스트
// ============================================

function testTelScheme() {
    appendMessage("info", "", "tel: 스킴 호출");
    window.location.href = "tel:010-0000-0000";
}

function testMailScheme() {
    appendMessage("info", "", "mailto: 스킴 호출");
    window.location.href = "mailto:test@example.com";
}

// ============================================
// UI 업데이트
// ============================================

/**
 * 메시지 박스에 로그 스타일로 메시지를 추가
 */
function appendMessage(tag, direction, body) {
    var messageBox = document.getElementById("messageBox");

    var now = new Date();
    var timestamp = [now.getHours(), now.getMinutes(), now.getSeconds()]
        .map(function (n) {
            return n < 10 ? "0" + n : n;
        })
        .join(":");

    var tagLabels = {
        request: "요청",
        success: "수신",
        fail: "실패",
        info: "정보",
        error: "오류",
    };
    var tagLabel = tagLabels[tag] || tag;

    var formattedBody = body.replace(/\n/g, "<br>");

    var directionHtml = direction
        ? '<span class="log-direction">' + direction + "</span>"
        : "";

    var html =
        '<div class="log-entry">' +
        '<span class="log-time">' + timestamp + "</span>" +
        '<span class="log-tag tag-' + tag + '">' + tagLabel + "</span>" +
        directionHtml +
        '<div class="log-body">' + formattedBody + "</div>" +
        "</div>";

    messageBox.innerHTML += html;
    messageBox.scrollTop = messageBox.scrollHeight;
}

function clearMessages() {
    var messageBox = document.getElementById("messageBox");
    messageBox.innerHTML = "";
}

// 페이지 로드 완료 시 Bridge 초기화 상태를 표시
document.addEventListener("DOMContentLoaded", function () {
    appendMessage("info", "", "Bridge 초기화 완료 (RPC mode)");
});

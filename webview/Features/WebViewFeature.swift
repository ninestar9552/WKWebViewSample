//
//  WebViewFeature.swift
//  webview
//
//  Created by TCA 변환 on 2/11/26.
//

import UIKit
import ComposableArchitecture

// ============================================================================
// MARK: - MVVM vs TCA: 아키텍처 비교
// ============================================================================
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ MVVM (기존 WebViewViewModel)                                            │
// │                                                                         │
// │ class WebViewViewModel {                                                │
// │     @Published var loadProgress: Double    ← 연속적 상태                  │
// │     @Event var error: Error                ← 일회성 이벤트                │
// │     @Event var urlToOpen: URL              ← 일회성 이벤트                │
// │     @Event var toastMessage: String        ← 일회성 이벤트                │
// │                                                                         │
// │     func handleBridgeMessage(request) {    ← 메서드 호출로 로직 실행       │
// │         bridgeHandler.sendToJS(...)        ← 사이드 이펙트 직접 호출       │
// │     }                                                                   │
// │ }                                                                       │
// ├─────────────────────────────────────────────────────────────────────────┤
// │ TCA (이 파일 — WebViewFeature)                                          │
// │                                                                         │
// │ @Reducer struct WebViewFeature {                                        │
// │     struct State {                                                      │
// │         var loadProgress: Double           ← 연속적 상태 (동일)           │
// │         var errorMessage: String?          ← 일회성 → Optional 상태       │
// │         var urlToOpen: URL?                ← 일회성 → Optional 상태       │
// │         var toastMessage: String?          ← 일회성 → Optional 상태       │
// │     }                                                                   │
// │     enum Action {                                                       │
// │         case bridgeMessageReceived(...)    ← 메서드 → 액션으로 변환       │
// │     }                                                                   │
// │     var body: Reduce { state, action in                                 │
// │         state.xxx = yyy                    ← 상태 변경은 여기서만          │
// │         return .run { bridgeClient.send }  ← 사이드 이펙트는 Effect로     │
// │     }                                                                   │
// │ }                                                                       │
// └─────────────────────────────────────────────────────────────────────────┘
//
// 핵심 차이 3가지:
// 1. 상태 변경: 아무 데서나 → Reducer body 안에서만 (예측 가능)
// 2. 사이드 이펙트: 직접 호출 → Effect로 명시적 반환 (추적 가능)
// 3. 이벤트: PassthroughSubject → Optional State + 소비 Action (테스트 가능)

// ============================================================================
// MARK: - @Reducer 매크로 버전 (비교용 — 일반적인 TCA 프로젝트에서 사용하는 형태)
// ============================================================================
//
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor 설정이 없는 프로젝트에서는
// 아래처럼 @Reducer 매크로를 사용하면 됨. 매크로가 자동으로 해주는 일:
// 1. Reducer 프로토콜 채택
// 2. Action에 @CasePathable 추가 (패턴 매칭용)
// 3. State에 @ObservableState 추가 (SwiftUI/UIKit observe 연동)
// 4. @Dependency를 프로퍼티로 선언 가능
//
// @Reducer
// struct WebViewFeature {
//
//     @ObservableState              // ← observe { } 블록에서 자동 감지 가능
//     struct State: Equatable {
//         var loadProgress: Double = 0.0
//         var errorMessage: String? = nil
//         var urlToOpen: URL? = nil
//         var toastMessage: String? = nil
//     }
//
//     enum Action {                 // ← @Reducer가 자동으로 @CasePathable 추가
//         case progressUpdated(Double)
//         case errorOccurred(String)
//         case bridgeMessageReceived(BridgeRequest)
//         case errorDismissed
//         case urlOpened
//         case toastShown
//     }
//
//     @Dependency(\.bridgeClient) var bridgeClient  // ← 프로퍼티로 선언 가능
//
//     var body: some ReducerOf<Self> {
//         Reduce { state, action in
//             // ... (아래 구현과 동일)
//         }
//     }
// }

// ============================================================================
// MARK: - 수동 구현 버전 (이 프로젝트에서 실제 사용하는 형태)
// ============================================================================
//
// 이 프로젝트는 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor 설정 때문에
// @Reducer 매크로가 생성하는 @CasePathable/@ObservableState 코드가 충돌.
// 그래서 Reducer 프로토콜을 직접 채택하여 구현.
//
// 차이점:
// - @Reducer 매크로 없음 → struct: Reducer 직접 채택
// - @ObservableState 없음 → store.publisher (Combine) 패턴으로 상태 구독
// - @Dependency 프로퍼티 없음 → Reduce 클로저 안에서 인라인 선언
// - @CasePathable 없음 → Presentation(.ifLet) 미사용
nonisolated struct WebViewFeature: Reducer {

    // MARK: - State

    /// 화면의 모든 상태를 하나의 값 타입(struct)으로 관리
    ///
    /// MVVM과의 차이:
    /// - MVVM: class 안에 @Published/@Event가 흩어져 있음
    /// - TCA: struct 하나에 모든 상태가 모여 있음 → 스냅샷 비교, 테스트가 쉬움
    ///
    /// ViewController에서의 상태 구독:
    /// - MVVM: viewModel.$loadProgress.sink { } (Combine)
    /// - TCA: store.publisher.loadProgress.sink { } (동일한 Combine 패턴)
    struct State: Equatable {

        /// 웹뷰 로딩 진행률 (0.0 ~ 1.0)
        /// - MVVM: @Published var loadProgress: Double = 0.0
        var loadProgress: Double = 0.0

        /// 에러 메시지 (nil이 아니면 알럿 표시)
        /// - MVVM: @Event var error: Error → PassthroughSubject로 한 번만 전달
        /// - TCA: Optional String → nil이 아니면 알럿 표시 → .errorDismissed로 초기화
        var errorMessage: String? = nil

        /// 열어야 할 URL (Bridge openUrl 요청)
        /// - MVVM: @Event var urlToOpen: URL → PassthroughSubject로 한 번만 전달
        /// - TCA: Optional URL → nil이 아니면 push → .urlOpened로 초기화
        var urlToOpen: URL? = nil

        /// 표시할 토스트 메시지 (Bridge showToast 요청)
        /// - MVVM: @Event var toastMessage: String
        /// - TCA: Optional String → nil이 아니면 토스트 표시 → .toastShown으로 초기화
        var toastMessage: String? = nil
    }

    // MARK: - Action

    /// 앱에서 일어날 수 있는 모든 이벤트를 열거
    ///
    /// MVVM과의 차이:
    /// - MVVM: viewModel.updateLoadProgress(0.5) — 메서드를 직접 호출
    /// - TCA: store.send(.progressUpdated(0.5)) — 액션을 "보냄"
    ///
    /// 장점: 모든 이벤트가 enum 한 곳에 정의되어 있어서
    ///       "이 화면에서 무슨 일이 일어날 수 있는가?"를 한눈에 파악 가능
    enum Action {

        // --- ViewController → Store (UI 이벤트) ---

        /// KVO estimatedProgress 값 변경
        /// - MVVM: viewModel.updateLoadProgress(progress)
        case progressUpdated(Double)

        /// 네비게이션 에러 발생
        /// - MVVM: viewModel.handleError(error)
        case errorOccurred(String)

        // --- BridgeHandler → Store (Bridge 이벤트) ---

        /// JS에서 Bridge 메시지가 도착함
        /// - MVVM: viewModel.handleBridgeMessage(request)
        case bridgeMessageReceived(BridgeRequest)

        // --- 상태 소비 (ViewController가 UI 처리 후 알림) ---

        /// 에러 알럿이 dismiss됨 → errorMessage를 nil로 초기화
        /// - MVVM에서는 PassthroughSubject라 자동 소비되어 이런 액션이 불필요했음
        /// - TCA에서는 State가 값을 보관하므로 명시적으로 초기화해야 함
        case errorDismissed

        /// ViewController가 URL push를 완료함 → urlToOpen을 nil로 초기화
        case urlOpened

        /// ViewController가 토스트를 표시함 → toastMessage를 nil로 초기화
        case toastShown
    }

    // MARK: - Reducer Body

    /// 모든 상태 변경 로직이 이 한 곳에 모여 있음
    ///
    /// (State, Action) → (State 변경, Effect 반환)
    ///
    /// MVVM과의 차이:
    /// - MVVM: 상태 변경이 ViewModel의 여러 메서드에 흩어져 있음
    /// - TCA: 이 switch문 하나만 보면 "어떤 액션이 상태를 어떻게 바꾸는지" 전부 파악 가능
    ///
    /// return .none = 사이드 이펙트 없음 (상태만 변경)
    /// return .run { } = 사이드 이펙트 있음 (비동기 작업 실행)
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            /// @Dependency를 Reduce 클로저 안에서 인라인으로 선언
            /// - MVVM: private weak var bridgeHandler: (any BridgeMessageSender)?
            /// - TCA: @Dependency(\.bridgeClient) — struct + 클로저 기반 의존성
            @Dependency(\.bridgeClient) var bridgeClient

            switch action {

            // MARK: Loading

            case .progressUpdated(let progress):
                /// MVVM 원본:
                /// func updateLoadProgress(_ progress: Double) {
                ///     self.loadProgress = progress
                /// }
                state.loadProgress = progress
                return .none

            // MARK: Error

            case .errorOccurred(let message):
                /// MVVM 원본:
                /// func handleError(_ error: Error) {
                ///     self.loadProgress = 0.0
                ///     self.error = error  // @Event → PassthroughSubject.send()
                /// }
                ///
                /// TCA: State에 에러 메시지를 저장
                /// → ViewController가 store.publisher.errorMessage를 구독하여 알럿 표시
                state.loadProgress = 0.0
                state.errorMessage = message
                return .none

            // MARK: Bridge

            case .bridgeMessageReceived(let request):
                /// MVVM 원본:
                /// func handleBridgeMessage(_ request: BridgeRequest) {
                ///     switch request.type {
                ///     case .greeting: handleGreeting(request)
                ///     ...
                ///     }
                /// }
                return handleBridgeMessage(request, state: &state, bridgeClient: bridgeClient)

            // MARK: Event Consumption

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case .urlOpened:
                state.urlToOpen = nil
                return .none

            case .toastShown:
                state.toastMessage = nil
                return .none
            }
        }
    }

    // MARK: - Bridge Message Handlers

    /// MVVM에서 private func handleXXX() 메서드들이었던 것
    ///
    /// 핵심 차이 — 사이드 이펙트 처리 방식:
    /// - MVVM: bridgeHandler.sendToJS() 를 메서드 안에서 직접 호출
    /// - TCA: Effect.run { } 을 반환하여 "이 사이드 이펙트를 실행해주세요" 라고 선언
    ///   → 이 덕분에 테스트에서 "어떤 Effect가 반환되었는지" 검증 가능

    private func handleBridgeMessage(
        _ request: BridgeRequest,
        state: inout State,
        bridgeClient: BridgeClient
    ) -> Effect<Action> {
        switch request.type {
        case .greeting:
            return handleGreeting(request, bridgeClient: bridgeClient)
        case .getUserInfo:
            return handleGetUserInfo(request, bridgeClient: bridgeClient)
        case .getAppVersion:
            return handleGetAppVersion(request, bridgeClient: bridgeClient)
        case .openUrl:
            return handleOpenUrl(request, state: &state, bridgeClient: bridgeClient)
        case .showToast:
            return handleShowToast(request, state: &state, bridgeClient: bridgeClient)
        }
    }

    private func handleGreeting(_ request: BridgeRequest, bridgeClient: BridgeClient) -> Effect<Action> {
        /// MVVM 원본:
        /// private func handleGreeting(_ request: BridgeRequest) {
        ///     guard let data = request.decodeData(GreetingRequestData.self) else {
        ///         bridgeHandler?.sendToJS(function: ..., response: ...)  ← 직접 호출
        ///         return
        ///     }
        ///     bridgeHandler?.sendToJS(function: ..., response: ...)      ← 직접 호출
        /// }
        ///
        /// TCA: sendToJS 호출이 Effect.run { } 안으로 이동
        /// → Reducer 본체는 순수하게 상태만 변경, 사이드 이펙트는 Effect로 분리
        let callback = request.callback

        guard let data = request.decodeData(GreetingRequestData.self) else {
            return .run { _ in
                bridgeClient.send(
                    function: callback,
                    response: BridgeResponse(success: false, message: "메시지 전송에 실패했습니다.")
                )
            }
        }

        let text = data.text
        return .run { _ in
            bridgeClient.send(
                function: callback,
                response: BridgeResponse(
                    success: true,
                    message: "메시지를 수신했습니다.",
                    data: GreetingResponseData(text: text)
                )
            )
        }
    }

    private func handleGetUserInfo(_ request: BridgeRequest, bridgeClient: BridgeClient) -> Effect<Action> {
        let callback = request.callback
        return .run { _ in
            bridgeClient.send(
                function: callback,
                response: BridgeResponse(
                    success: true,
                    message: "사용자 정보를 불러왔습니다.",
                    data: UserInfoResponseData(
                        name: "차순혁",
                        device: await UIDevice.current.model,
                        osVersion: await UIDevice.current.systemVersion
                    )
                )
            )
        }
    }

    private func handleGetAppVersion(_ request: BridgeRequest, bridgeClient: BridgeClient) -> Effect<Action> {
        let callback = request.callback
        return .run { _ in
            let appVersion = await Bundle.main.appVersion
            bridgeClient.send(
                function: callback,
                response: BridgeResponse(
                    success: true,
                    message: "앱 버전 정보를 불러왔습니다.",
                    data: AppVersionResponseData(
                        appVersion: appVersion,
                        osVersion: await UIDevice.current.systemVersion,
                        device: await UIDevice.current.modelIdentifier
                    )
                )
            )
        }
    }

    private func handleOpenUrl(
        _ request: BridgeRequest,
        state: inout State,
        bridgeClient: BridgeClient
    ) -> Effect<Action> {
        let callback = request.callback

        guard let data = request.decodeData(OpenUrlRequestData.self),
              let url = URL(string: data.url) else {
            return .run { _ in
                bridgeClient.send(
                    function: callback,
                    response: BridgeResponse(success: false, message: "유효하지 않은 URL입니다.")
                )
            }
        }

        /// MVVM: self.urlToOpen = url  (@Event → PassthroughSubject.send → ViewController가 구독)
        /// TCA: state.urlToOpen = url  (State 변경 → store.publisher에서 감지)
        state.urlToOpen = url

        return .run { _ in
            bridgeClient.send(
                function: callback,
                response: BridgeResponse(success: true, message: "새 화면에서 URL을 엽니다.")
            )
        }
    }

    private func handleShowToast(
        _ request: BridgeRequest,
        state: inout State,
        bridgeClient: BridgeClient
    ) -> Effect<Action> {
        let callback = request.callback

        guard let data = request.decodeData(ShowToastRequestData.self) else {
            return .run { _ in
                bridgeClient.send(
                    function: callback,
                    response: BridgeResponse(success: false, message: "메시지가 없습니다.")
                )
            }
        }

        /// MVVM: self.toastMessage = data.message
        /// TCA: state.toastMessage = data.message
        state.toastMessage = data.message

        return .run { _ in
            bridgeClient.send(
                function: callback,
                response: BridgeResponse(success: true, message: "토스트를 표시합니다.")
            )
        }
    }
}

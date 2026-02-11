//
//  ViewController+Bindings.swift
//  webview
//
//  Created by 차순혁 on 2/4/26.
//

import UIKit
import WebKit
import Combine

// ============================================================================
// MARK: - MVVM vs TCA: 바인딩 방식 비교
// ============================================================================
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ MVVM (기존)                                                             │
// │                                                                         │
// │ viewModel.$loadProgress.sink { }    ← @Published Combine 구독          │
// │ viewModel.$error.sink { }           ← @Event (PassthroughSubject) 구독  │
// │ viewModel.$urlToOpen.sink { }       ← @Event 구독                       │
// │ viewModel.$toastMessage.sink { }    ← @Event 구독                       │
// ├─────────────────────────────────────────────────────────────────────────┤
// │ TCA (변환 후)                                                           │
// │                                                                         │
// │ store.publisher.loadProgress.sink { }   ← Store publisher 구독          │
// │ store.publisher.errorMessage.sink { }   ← Store publisher 구독          │
// │ store.publisher.urlToOpen.sink { }      ← Store publisher 구독          │
// │ store.publisher.toastMessage.sink { }   ← Store publisher 구독          │
// │                                                                         │
// │ 차이점:                                                                  │
// │ - @Event는 한 번 전달 후 자동 소비 (PassthroughSubject)                   │
// │ - TCA는 Optional State로 유지 → UI 처리 후 소비 Action을 보내야 함       │
// │   예: store.send(.errorDismissed) → state.errorMessage = nil            │
// └─────────────────────────────────────────────────────────────────────────┘

/// Store ↔ ViewController Combine 바인딩
/// - MVVM: ViewModel의 @Published/@Event를 Combine .sink로 구독
/// - TCA: Store의 publisher를 Combine .sink로 구독 (패턴이 거의 동일)
extension ViewController {

    // MARK: - Setup Bindings

    func setupBindings() {
        bindProgress()
        bindError()
        bindOpenUrl()
        bindToast()
        bindAppLifecycle()
    }

    // MARK: - Progress

    /// KVO 퍼블리셔로 WebView의 estimatedProgress를 관찰하여 Store에 전달
    /// - MVVM: webView KVO → viewModel.updateLoadProgress()
    /// - TCA: webView KVO → store.send(.progressUpdated())
    private func bindProgress() {
        // WebView → Store
        /// MVVM: webView.publisher(for: \.estimatedProgress)
        ///           .sink { self?.viewModel.updateLoadProgress($0) }
        /// TCA:  webView.publisher(for: \.estimatedProgress)
        ///           .sink { self?.store.send(.progressUpdated($0)) }
        webView.publisher(for: \.estimatedProgress)
            .sink { [weak self] in self?.store.send(.progressUpdated($0)) }
            .store(in: &cancellables)

        // Store → UI
        /// MVVM: viewModel.$loadProgress.sink { self?.updateProgressView(progress: $0) }
        /// TCA:  store.publisher.loadProgress.sink { self?.updateProgressView(progress: $0) }
        store.publisher.loadProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateProgressView(progress: $0) }
            .store(in: &cancellables)
    }

    private func updateProgressView(progress: Double) {
        if progress > 0 && progress < 1.0 {
            showProgress(progress)
        } else if progress >= 1.0 {
            completeProgress()
        } else {
            resetProgress()
        }
    }

    private func showProgress(_ progress: Double) {
        progressView.isHidden = false
        progressView.alpha = 1
        progressView.setProgress(Float(progress), animated: true)
    }

    private func completeProgress() {
        progressView.setProgress(1.0, animated: true)
        UIView.animate(withDuration: 0.3, delay: 0.5) { [weak self] in
            self?.progressView.alpha = 0
        } completion: { [weak self] _ in
            self?.progressView.isHidden = true
            self?.progressView.setProgress(0, animated: false)
        }
    }

    private func resetProgress() {
        progressView.isHidden = true
        progressView.setProgress(0, animated: false)
    }

    // MARK: - Error

    /// 에러 메시지를 구독하여 알럿 표시
    /// - MVVM: @Event var error → PassthroughSubject → 자동 소비 (한 번만 전달)
    /// - TCA: Optional State → 알럿 표시 후 .errorDismissed 액션으로 nil 초기화
    private func bindError() {
        store.publisher.errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.showErrorAlert(message)
            }
            .store(in: &cancellables)
    }

    // MARK: - Open URL

    /// URL 열기 이벤트를 구독하여 새 화면으로 push
    /// - MVVM: @Event var urlToOpen → PassthroughSubject → 자동 소비
    /// - TCA: Optional State → push 후 .urlOpened 액션으로 nil 초기화
    private func bindOpenUrl() {
        store.publisher.urlToOpen
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] url in
                let webVC = ViewController(url: url)
                self?.navigationController?.pushViewController(webVC, animated: true)
                self?.store.send(.urlOpened)
            }
            .store(in: &cancellables)
    }

    // MARK: - Toast

    /// 토스트 메시지를 구독하여 토스트 표시
    /// - MVVM: @Event var toastMessage → PassthroughSubject → 자동 소비
    /// - TCA: Optional State → 토스트 표시 후 .toastShown 액션으로 nil 초기화
    private func bindToast() {
        store.publisher.toastMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.showToast(message)
                self?.store.send(.toastShown)
            }
            .store(in: &cancellables)
    }

    private func showToast(_ message: String) {
        let toastLabel = UILabel()
        toastLabel.text = message
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.font = .systemFont(ofSize: 14, weight: .medium)
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toastLabel.layer.cornerRadius = 8
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        toastLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(toastLabel)

        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            toastLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            toastLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            toastLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])

        // 패딩을 위한 인셋 설정
        toastLabel.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

        // 텍스트 인셋 적용을 위해 너비 제약 추가
        let padding: CGFloat = 32
        let maxWidth = view.bounds.width - 40 - padding
        let textWidth = message.size(withAttributes: [.font: toastLabel.font!]).width
        let labelWidth = min(textWidth + padding, maxWidth)
        toastLabel.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        // 애니메이션: 페이드 인 → 유지 → 페이드 아웃
        UIView.animate(withDuration: 0.3) {
            toastLabel.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0) {
                toastLabel.alpha = 0
            } completion: { _ in
                toastLabel.removeFromSuperview()
            }
        }
    }

    // MARK: - App Lifecycle (백화현상 복구)

    private func bindAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recoverFromWhiteScreenIfNeeded()
            }
            .store(in: &cancellables)
    }

    /// 백화현상 복구: WebContent 프로세스 종료 후 앱이 다시 활성화되면 마지막 URL로 재로딩
    private func recoverFromWhiteScreenIfNeeded() {
        guard needsReload, let url = lastLoadedURL else { return }
        print("🔄 백화현상 복구: \(url)")
        needsReload = false
        webView.load(URLRequest(url: url))
    }

    // MARK: - Error Alert

    /// 에러 알럿 표시
    /// - MVVM: Error 객체를 받아서 localizedDescription 표시
    /// - TCA: 이미 String으로 변환된 에러 메시지를 받아서 표시
    ///   알럿 dismiss 후 store.send(.errorDismissed)로 상태 초기화
    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(
            title: "오류",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            /// TCA에서 추가된 부분: 알럿이 닫힌 후 상태를 초기화
            /// - MVVM: @Event는 PassthroughSubject라 자동으로 소비되어 별도 처리 불필요
            /// - TCA: State에 값이 남아있으므로 명시적으로 nil로 초기화해야 함
            self?.store.send(.errorDismissed)
        })
        present(alert, animated: true)
    }
}

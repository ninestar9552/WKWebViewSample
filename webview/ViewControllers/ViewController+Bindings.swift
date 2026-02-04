//
//  ViewController+Bindings.swift
//  webview
//
//  Created by 차순혁 on 2/4/26.
//

import UIKit
import Combine

/// ViewModel ↔ ViewController Combine 바인딩
extension ViewController {

    // MARK: - Setup Bindings

    func setupBindings() {
        bindProgress()
        bindError()
        bindOpenUrl()
    }

    // MARK: - Progress

    /// KVO 퍼블리셔로 WebView의 estimatedProgress를 관찰하여 ViewModel에 전달
    private func bindProgress() {
        // WebView → ViewModel
        webView.publisher(for: \.estimatedProgress)
            .sink { [weak self] in self?.viewModel.updateLoadProgress($0) }
            .store(in: &cancellables)

        // ViewModel → UI
        viewModel.$loadProgress
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
        UIView.animate(withDuration: 0.3, delay: 0.5) {
            self.progressView.alpha = 0
        } completion: { _ in
            self.progressView.isHidden = true
            self.progressView.setProgress(0, animated: false)
        }
    }

    private func resetProgress() {
        progressView.isHidden = true
        progressView.setProgress(0, animated: false)
    }

    // MARK: - Error

    private func bindError() {
        viewModel.$error
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.showErrorAlert(error)
            }
            .store(in: &cancellables)
    }

    // MARK: - Open URL

    private func bindOpenUrl() {
        viewModel.$urlToOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                let webVC = ViewController(url: url)
                self?.navigationController?.pushViewController(webVC, animated: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Error Alert

    private func showErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "오류",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }
}

//
//  PopupNavigationBar.swift
//  webview
//
//  Created by 차순혁 on 2/3/26.
//

import UIKit

/// 팝업 WebView 상단에 표시되는 네비게이션 바
/// - X 버튼으로 팝업 닫기 기능 제공
/// - 하단 separator로 WebView 영역과 구분
final class PopupNavigationBar: UIView {

    /// 닫기 버튼 탭 이벤트
    var onClose: (() -> Void)?

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .label
        return button
    }()

    private let separator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .systemBackground

        addSubview(closeButton)
        addSubview(separator)

        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    @objc private func closeButtonTapped() {
        onClose?()
    }
}

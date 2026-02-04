//
//  SceneDelegate.swift
//  webview
//
//  Created by 차순혁 on 1/25/26.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let rootVC = ViewController()
        let navigationController = UINavigationController(rootViewController: rootVC)
        navigationController.setNavigationBarHidden(true, animated: false)

        /// Navigation bar 숨김 시 interactive pop gesture가 비활성화되는 문제 해결
        /// - delegate를 nil로 설정하여 기본 제스처 동작 허용
        navigationController.interactivePopGestureRecognizer?.delegate = nil

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
    }

}


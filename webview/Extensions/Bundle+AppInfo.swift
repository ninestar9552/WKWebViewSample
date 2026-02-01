//
//  Bundle+AppInfo.swift
//  webview
//
//  Created by 차순혁 on 2/2/26.
//

import Foundation

extension Bundle {

    /// 앱의 표시 버전 (CFBundleShortVersionString, 예: "1.0.0")
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

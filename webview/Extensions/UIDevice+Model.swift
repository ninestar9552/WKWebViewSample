//
//  UIDevice+Model.swift
//  webview
//
//  Created by 차순혁 on 2/2/26.
//

import UIKit

extension UIDevice {

    /// 하드웨어 모델 식별자를 반환 (예: "iPhone15,2", "iPad14,1")
    /// - utsname의 machine 필드에서 실제 하드웨어 모델명을 가져옴
    var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? model
            }
        }
    }
}

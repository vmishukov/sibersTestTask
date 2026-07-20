//
//  DownloadItem.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 20.07.2026.
//

import Foundation

struct DownloadItem {
    
    let url: String
    let title: String
    var progress: Float = 0
    var isPaused: Bool = false
}

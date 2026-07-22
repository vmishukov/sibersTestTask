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
    var progress: ProgressModel
    var isPaused: Bool = false
}

struct ProgressModel {
    let totalSegments: Int
    var progress: Float = 0
    var downloadedSegments: Int = 0
    var activeSegments: Int = 0
    var expectedActive: Int = 0
}

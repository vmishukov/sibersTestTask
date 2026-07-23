//
//  DownloadItem.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 20.07.2026.
//

enum DownloadItemState {
    case waiting
    case downloading
    case paused
}

class DownloadItem {
    let url: String
    var title: String
    var progress: ProgressModel
    var state: DownloadItemState = .waiting
    var isPaused: Bool { state == .paused }
    
    init(url: String, title: String, progress: ProgressModel) {
        self.url = url
        self.title = title
        self.progress = progress
    }
}

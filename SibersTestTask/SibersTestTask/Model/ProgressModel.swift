//
//  ProgressModel.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 23.07.2026.
//

struct ProgressModel {
    
    let totalSegments: Int
    var progress: Float = 0
    var downloadedSegments: Int = 0
    var activeSegments: Int = 0
    var expectedActive: Int = 0
}

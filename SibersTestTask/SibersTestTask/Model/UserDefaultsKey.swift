//
//  UserDefaultsKey.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 04.08.2026.
//

import Foundation

enum UserDefaultsKey: String, CaseIterable {
    case maxSegmentsPerFile
    case maxSegmentSizeMB
    case maxConcurrentFiles
    case retryAttempts
    
    var defaultValue: Int {
        switch self {
        case .maxSegmentsPerFile: return 5
        case .maxSegmentSizeMB: return 5
        case .maxConcurrentFiles: return 3
        case .retryAttempts: return 3
        }
    }
}

extension UserDefaults {
    func integer(forKey key: UserDefaultsKey) -> Int {
        integer(forKey: key.rawValue)
    }
    
    func set(_ value: Int, forKey key: UserDefaultsKey) {
        set(value, forKey: key.rawValue)
    }
    
    func registerDownloadDefaults() {
        register(defaults: Dictionary(uniqueKeysWithValues: UserDefaultsKey.allCases.map {
            ($0.rawValue, $0.defaultValue)
        }))
    }
}

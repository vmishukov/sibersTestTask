//
//  FileWriter.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 23.07.2026.
//

import Foundation

actor FileWriter {
    private let handle: FileHandle
    
    init(handle: FileHandle) {
        self.handle = handle
    }
    
    func write(data: Data, at offset: UInt64) throws {
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: data)
    }
    
    func close() throws {
        try handle.close()
    }
}

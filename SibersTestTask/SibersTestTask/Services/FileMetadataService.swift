//
//  FileMetadataService.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 23.07.2026.
//

import Foundation
import UniformTypeIdentifiers

final class FileMetadataService {
    private let session: URLSession
    
    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }
    
    func fetchMetadata(from url: URL) async throws -> (size: Int64, ext: String?) {
        do {
            return try await fetchMetadataViaHead(from: url)
        } catch {
            return try await fetchMetadataViaGet(from: url)
        }
    }
}

// MARK: - Private implementation
private extension FileMetadataService {
    
    func fetchMetadataViaHead(from url: URL) async throws -> (size: Int64, ext: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExtensionError.invalidResponse
        }
        
        let fileSize = httpResponse.expectedContentLength
        guard fileSize > 0 else {
            throw ExtensionError.cannotDetermineSize
        }
        
        let ext = fileExtension(from: httpResponse)
        return (fileSize, ext)
    }
    
    func fetchMetadataViaGet(from url: URL) async throws -> (size: Int64, ext: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExtensionError.invalidResponse
        }
        
        let fileSize: Int64 = {
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
               let totalString = contentRange.components(separatedBy: "/").last,
               let total = Int64(totalString) {
                return total
            }
            return httpResponse.expectedContentLength
        }()
        
        guard fileSize > 0 else {
            throw ExtensionError.cannotDetermineSize
        }
        
        let ext = fileExtension(from: httpResponse)
        return (fileSize, ext)
    }
    
    func fileExtension(from response: HTTPURLResponse) -> String? {
        guard let mimeType = response.mimeType,
              let utType = UTType(mimeType: mimeType) else { return nil }
        return utType.preferredFilenameExtension
    }
}

//
//  DownloadNetworkManager.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 18.07.2026.
//

import Foundation

final class DownloadNetworkManager {
    
    func downloadFile(from urlString: String) async throws -> (URL, String?) {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (localURL, response) = try await URLSession.shared.download(from: url)
        return (localURL, response.suggestedFilename)
    }
}

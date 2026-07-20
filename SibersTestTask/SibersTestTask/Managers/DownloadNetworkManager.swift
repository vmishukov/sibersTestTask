//
//  DownloadNetworkManager.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 18.07.2026.
//

import Foundation
import UniformTypeIdentifiers

enum ExtensionError: Error {
    case invalidResponse
}

enum DownloadStatus {
    case progress(Double)
    case success(localURL: URL, fileName: String?)
    case failure(Error)
}

actor DownloadNetworkManager: NSObject {
    
    private var continuations: [URL: AsyncStream<DownloadStatus>.Continuation] = [:]
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    // Главный метод для запуска загрузки
    func downloadFile(from urlString: String) throws -> AsyncStream<DownloadStatus> {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        // Создаем AsyncStream, который будет возвращать прогресс и результат
        return AsyncStream { continuation in
            self.continuations[url] = continuation
            
            let task = session.downloadTask(with: url)
            task.resume()
            
            // Если клиент отменит Swift Task, отменяем и загрузку сессии
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    func fetchFileExtension(from urlString: String) async throws -> String? {
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              let mimeType = httpResponse.mimeType else {
            throw ExtensionError.invalidResponse
        }
        
        if let utType = UTType(mimeType: mimeType) {
            return utType.preferredFilenameExtension
        }
        
        return nil
    }
}

// MARK: - URLSessionDownloadDelegate
extension DownloadNetworkManager: URLSessionDownloadDelegate {
    
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let url = downloadTask.originalRequest?.url,
              totalBytesExpectedToWrite > 0 else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        Task { [weak self] in
            await self?.send(status: .progress(progress), for: url)
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let url = downloadTask.originalRequest?.url else { return }
        
        // Перемещаем файл во временную директорию, так как location удалится после выхода из метода
        let fileManager = FileManager.default
        let uniqueURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            if fileManager.fileExists(atPath: uniqueURL.path) {
                try fileManager.removeItem(at: uniqueURL)
            }
            try fileManager.moveItem(at: location, to: uniqueURL)
            
            let filename = downloadTask.response?.suggestedFilename
            
            Task { [weak self] in
                await self?.send(status: .success(localURL: uniqueURL, fileName: filename), for: url)
                await self?.finishStream(for: url)
            }
        } catch {
            Task { [weak self] in
                await self?.send(status: .failure(error), for: url)
                await self?.finishStream(for: url)
            }
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let url = task.originalRequest?.url, let error = error else { return }
        
        if (error as NSError).code == NSURLErrorCancelled { return }
        
        Task { [weak self] in
            await self?.send(status: .failure(error), for: url)
            await self?.finishStream(for: url)
        }
    }
}

// MARK: - PRIVATE METHODS
private extension DownloadNetworkManager {
    
    private func send(status: DownloadStatus, for url: URL) {
        continuations[url]?.yield(status)
    }
    
    private func finishStream(for url: URL) {
        continuations[url]?.finish()
        continuations.removeValue(forKey: url)
    }
}

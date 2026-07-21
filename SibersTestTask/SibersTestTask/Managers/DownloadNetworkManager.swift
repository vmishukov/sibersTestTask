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
    case pausedByRequest
    case success(localURL: URL, fileName: String?)
    case failure(Error)
}

actor DownloadNetworkManager: NSObject {
    
    private var continuations: [URL: AsyncStream<DownloadStatus>.Continuation] = [:]
    
    private var resumeDataStore: [URL: Data] = [:]
    private var activeDownloadTasks: [URL: URLSessionDownloadTask] = [:]
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    func downloadFile(from urlString: String) throws -> AsyncStream<DownloadStatus> {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        return AsyncStream { continuation in
            self.continuations[url] = continuation
            
            let task: URLSessionDownloadTask
            
            if let resumeData = self.resumeDataStore[url] {
                task = session.downloadTask(withResumeData: resumeData)
                self.resumeDataStore.removeValue(forKey: url)
            } else {
                task = session.downloadTask(with: url)
            }
            
            self.activeDownloadTasks[url] = task
            task.resume()
            
            continuation.onTermination = { _ in
                // Здесь ничего не делаем, отмену контролируем вручную, чтобы не ломать логику паузы
            }
        }
    }
    
    // НОВЫЙ МЕТОД: Постановка на паузу
    func pauseDownload(for urlString: String) {
        guard let url = URL(string: urlString),
              let task = activeDownloadTasks[url] else { return }
        task.cancel { [weak self] resumeDataOrNil in
            guard let resumeData = resumeDataOrNil else { return }
            
            Task { [weak self] in
                await self?.saveResumeData(resumeData, for: url)
                await self?.send(status: .pausedByRequest, for: url)
                await self?.finishStream(for: url)
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
    
    func send(status: DownloadStatus, for url: URL) {
        continuations[url]?.yield(status)
    }
    
    func finishStream(for url: URL) {
        continuations[url]?.finish()
        continuations.removeValue(forKey: url)
    }
    
    func saveResumeData(_ data: Data, for url: URL) {
        resumeDataStore[url] = data
        activeDownloadTasks.removeValue(forKey: url)
    }
}

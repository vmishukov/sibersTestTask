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
    case cannotDetermineSize
}

enum DownloadStatus {
    case progress(ProgressModel)
    case pausedByRequest
    case success(localURL: URL, fileName: String?)
    case failure(Error)
}
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
actor DownloadNetworkManager: NSObject {
    
    private var continuations: [URL: AsyncStream<DownloadStatus>.Continuation] = [:]
    private var activeFileTasks: [URL: Task<Void, Never>] = [:]
    private var downloadedSegmentsMap: [URL: [Int: Bool]] = [:]
    
    private(set) var fileURLsMap: [URL: URL] = [:]
    
    private var activeSegmentTasks: [URL: [Task<Void, Never>]] = [:]
    private var activeSegmentsCountPerURL: [URL: Int] = [:]
    private var nextSegmentIndexPerURL: [URL: Int] = [:]
    private var activeFileHandles: [URL: FileHandle] = [:]
    
    private let segmentSize: Int64 = 5 * 1024 * 1024
    private let maxConcurrentSegments = 5
    private var maxRetries = 3
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 10
        return URLSession(configuration: configuration)
    }()
    
    func downloadFile(from urlString: String) throws -> AsyncStream<DownloadStatus> {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        return AsyncStream { continuation in
            self.continuations[url] = continuation
            
            let fileTask = Task {
                do {
                    let metadata = try await self.getFileMetadata(from: url)
                    let totalSegments = Int(ceil(Double(metadata.size) / Double(self.segmentSize)))
                    if var existingMap = downloadedSegmentsMap[url] {
                        for i in 0..<totalSegments {
                            if existingMap[i] == nil { existingMap[i] = false }
                        }
                        downloadedSegmentsMap[url] = existingMap
                    } else {
                        initializeSegmentsMapIfNeeded(for: url, totalSegments: totalSegments)
                    }
                    
                    let finalFileName = self.makeFileName(for: url, extension: metadata.ext)
                    
                    self.initializeSegmentsMapIfNeeded(for: url, totalSegments: totalSegments)
                    
                    let destinationURL: URL
                    if let existingURL = self.fileURLsMap[url] {
                        destinationURL = existingURL
                    } else {
                        destinationURL = try self.createTemporaryFile()
                        self.fileURLsMap[url] = destinationURL
                    }
                    
                    // Если уже есть открытый дескриптор для этого URL, закрываем его (на всякий случай)
                    if let oldHandle = activeFileHandles[url] {
                        try? oldHandle.close()
                        activeFileHandles.removeValue(forKey: url)
                    }
                    
                    guard let fileHandle = try? FileHandle(forWritingTo: destinationURL) else {
                        throw URLError(.cannotCreateFile)
                    }
                    activeFileHandles[url] = fileHandle
                    defer {
                        // При выходе из области видимости (успех/ошибка) закроем дескриптор, если он ещё не закрыт
                        if activeFileHandles[url] == fileHandle {
                            try? fileHandle.close()
                            activeFileHandles.removeValue(forKey: url)
                        }
                    }
                    try await self.runDispatcherLoop(
                        url: url,
                        fileSize: metadata.size,
                        totalSegments: totalSegments,
                        fileHandle: fileHandle
                    )
                    
                    if !Task.isCancelled {
                        // Очищаем кэш только при 100% УСПЕХЕ
                        self.downloadedSegmentsMap.removeValue(forKey: url)
                        self.fileURLsMap.removeValue(forKey: url)
                        self.activeSegmentTasks.removeValue(forKey: url)
                        activeSegmentsCountPerURL.removeValue(forKey: url)
                        nextSegmentIndexPerURL.removeValue(forKey: url)
                        try? activeFileHandles[url]?.close()
                        activeFileHandles.removeValue(forKey: url)
                        continuation.yield(.success(localURL: destinationURL, fileName: finalFileName))
                        self.finishStream(for: url)
                    }
                    
                } catch {
                    continuation.yield(.failure(error))
                    self.finishStream(for: url)
                }
            }
            
            self.activeFileTasks[url] = fileTask
        }
    }
    
    func pauseDownload(for urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        activeFileTasks[url]?.cancel()
        activeFileTasks.removeValue(forKey: url)
        
        activeSegmentTasks[url]?.forEach { $0.cancel() }
        activeSegmentTasks.removeValue(forKey: url)
        
        if let handle = activeFileHandles[url] {
            try? handle.close()
            activeFileHandles.removeValue(forKey: url)
        }
        
        activeSegmentsCountPerURL.removeValue(forKey: url)
        nextSegmentIndexPerURL.removeValue(forKey: url)
        
        send(status: .pausedByRequest, for: url)
        finishStream(for: url)
    }
    
    func fetchFileExtension(from urlString: String) async throws -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let metadata = try await getFileMetadata(from: url)
        return metadata.ext
    }
    
    // MARK: Сохранение/восстановление состояния
    
    func saveState() async throws -> Data {
        var state: [[String: Any]] = []
        for (url, fileURL) in fileURLsMap {
            guard let segments = downloadedSegmentsMap[url] else { continue }
            let segmentIndices = segments.filter { $0.value }.map { $0.key }
            let dict: [String: Any] = [
                "url": url.absoluteString,
                "filePath": fileURL.path,
                "downloadedSegments": segmentIndices
            ]
            state.append(dict)
        }
        return try JSONSerialization.data(withJSONObject: state, options: .prettyPrinted)
    }

    
    func loadState(from data: Data) {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for item in array {
            guard let urlString = item["url"] as? String,
                  let url = URL(string: urlString),
                  let filePath = item["filePath"] as? String,
                  let segments = item["downloadedSegments"] as? [Int]
            else { continue }
            
            let fileURL = URL(fileURLWithPath: filePath)
            // Проверяем, существует ли временный файл
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            
            fileURLsMap[url] = fileURL
            
            // Восстанавливаем карту сегментов. Общее число сегментов получим позже при запуске downloadFile.
            // Пока заполним известные завершённые.
            var map = [Int: Bool]()
            for idx in segments { map[idx] = true }
            downloadedSegmentsMap[url] = map
        }
    }
}

private extension DownloadNetworkManager {
    
    func runDispatcherLoop(url: URL, fileSize: Int64, totalSegments: Int, fileHandle: FileHandle) async throws {
        
        nextSegmentIndexPerURL[url] = getFirstUnfinishedSegmentIndex(for: url, totalSegments: totalSegments)
        activeSegmentsCountPerURL[url] = 0
        
        let fileWriter = FileWriter(handle: fileHandle)
        
        while try getDownloadedCount(for: url) < totalSegments {
            if Task.isCancelled { break }
            
            let active = activeSegmentsCountPerURL[url] ?? 0
            var nextIdx = nextSegmentIndexPerURL[url] ?? 0
            
            if active < maxConcurrentSegments && nextIdx < totalSegments {
                // Пропускаем уже загруженные сегменты
                while nextIdx < totalSegments && downloadedSegmentsMap[url]?[nextIdx] == true {
                    nextIdx += 1
                }
                guard nextIdx < totalSegments else { continue }
                
                let segmentToDownload = nextIdx
                nextIdx += 1
                nextSegmentIndexPerURL[url] = nextIdx
                
                let previousActive = activeSegmentsCountPerURL[url] ?? 0
                let newActive = previousActive + 1
                activeSegmentsCountPerURL[url] = newActive
                
                let startByte = Int64(segmentToDownload) * segmentSize
                let endByte = min(startByte + segmentSize - 1, fileSize - 1)
                
                // Уведомление о прогрессе (исправлено на основе скачанных сегментов)
                let downloaded = (try? getDownloadedCount(for: url)) ?? 0
                let currentProgress = min(Float(downloaded) * Float(segmentSize) / Float(fileSize), 1.0)
                let progressModel = ProgressModel(
                    totalSegments: totalSegments,
                    progress: currentProgress,
                    downloadedSegments: downloaded,
                    activeSegments: newActive,
                    expectedActive: min(maxConcurrentSegments, totalSegments - downloaded)
                )
                continuations[url]?.yield(.progress(progressModel))
                
                // Запуск задачи сегмента – БЕЗ inout-параметров!
                let segmentTask = Task { [url] in
                    await self.executeSegmentDownload(
                        url: url,
                        index: segmentToDownload,
                        start: startByte,
                        end: endByte,
                        fileSize: fileSize,
                        totalSegments: totalSegments,
                        fileWriter: fileWriter   // ← теперь передаётся FileWriter
                    )
                    self.decrementActiveSegments(for: url)
                }
                
                if activeSegmentTasks[url] == nil {
                    activeSegmentTasks[url] = []
                }
                activeSegmentTasks[url]?.append(segmentTask)
            }
            
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        // После цикла закрываем писатель (если всё скачалось успешно)
        try? await fileWriter.close()
    }
    
    func executeSegmentDownload(
        url: URL,
        index: Int,
        start: Int64,
        end: Int64,
        fileSize: Int64,
        totalSegments: Int,
        fileWriter: FileWriter
    ) async {
        var isSuccess = false
        var lastError: Error?
        
        for _ in 0..<maxRetries {
            if Task.isCancelled { return }
            do {
                let segmentData = try await self.downloadRangeWithTimeout(from: url, start: start, end: end, seconds: 10)
                try await fileWriter.write(data: segmentData, at: UInt64(start))
                self.updateSegmentState(url: url, index: index, isDownloaded: true)
                isSuccess = true
                break
            } catch {
                if Task.isCancelled { return }
                lastError = error
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        
        // Обновляем прогресс в любом случае
        let downloaded = (try? self.getDownloadedCount(for: url)) ?? 0
        let remainingSegments = totalSegments - downloaded
        let currentExpectedActive = min(maxConcurrentSegments, remainingSegments)
        
        if isSuccess {
            let progress = Float(downloaded * Int(segmentSize)) / Float(fileSize)
            let model = ProgressModel(totalSegments: totalSegments,
                                      progress: min(1.0, progress),
                                      downloadedSegments: downloaded,
                                      activeSegments: activeSegmentsCountPerURL[url] ?? 0,
                                      expectedActive: currentExpectedActive)
            continuations[url]?.yield(.progress(model))
        } else {
            // Неудачный сегмент: откатываем индекс, шлём ошибку, но НЕ чистим состояние!
            resetNextSegmentIndex(for: url, to: index)
            
            let progress = Float(downloaded * Int(segmentSize)) / Float(fileSize)
            let model = ProgressModel(totalSegments: totalSegments,
                                      progress: min(1.0, progress),
                                      downloadedSegments: downloaded,
                                      activeSegments: activeSegmentsCountPerURL[url] ?? 0,
                                      expectedActive: currentExpectedActive)
            continuations[url]?.yield(.progress(model))
            
            // Даем небольшую паузу, чтобы UI успел обновиться
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            let finalError = lastError ?? URLError(.networkConnectionLost)
            continuations[url]?.yield(.failure(finalError))
            
            // Завершаем стрим для этого URL, но НЕ удаляем downloadedSegmentsMap, fileURLsMap и т.д.
            // Это позволит при следующем вызове downloadFile продолжить с того же места.
            if let handle = activeFileHandles[url] {
                try? handle.close()
                activeFileHandles.removeValue(forKey: url)
            }
            // Отменяем только задачу этого файла, но не чистим карты.
            activeFileTasks[url]?.cancel()
            activeFileTasks.removeValue(forKey: url)
            
            continuations[url]?.finish()
            continuations.removeValue(forKey: url)
            activeSegmentsCountPerURL.removeValue(forKey: url)
            nextSegmentIndexPerURL.removeValue(forKey: url)
            // ⚠️ downloadedSegmentsMap и fileURLsMap сохраняем!
        }
    }
    
    func getFileMetadata(from url: URL) async throws -> (size: Int64, ext: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ExtensionError.invalidResponse
            }
            
            let fileSize = httpResponse.expectedContentLength
            
            // Если сервер запретил HEAD или вернул некорректный размер (-1), уходим в блок catch
            guard fileSize > 0 else { throw ExtensionError.cannotDetermineSize }
            
            var fileExtension: String? = nil
            if let mimeType = httpResponse.mimeType, let utType = UTType(mimeType: mimeType) {
                fileExtension = utType.preferredFilenameExtension
            }
            
            return (fileSize, fileExtension)
        } catch {
            // Сервер ECMA или аналогичный сбросил HEAD запрос. Пробуем получить размер через GET:
            return try await getMetadataViaGet(from: url)
        }
    }
    
    private func getMetadataViaGet(from url: URL) async throws -> (Int64, String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 ...", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,...", forHTTPHeaderField: "Accept")
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExtensionError.invalidResponse
        }
        let fileSize = httpResponse.expectedContentLength
        guard fileSize > 0 else { throw ExtensionError.cannotDetermineSize }
        
        var fileExtension: String? = nil
        if let mimeType = httpResponse.mimeType, let utType = UTType(mimeType: mimeType) {
            fileExtension = utType.preferredFilenameExtension
        }
        return (fileSize, fileExtension)
    }
    
    func downloadRange(from url: URL, start: Int64, end: Int64) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 15
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
    
    func makeFileName(for url: URL, extension ext: String?) -> String {
        let baseName = url.lastPathComponent.isEmpty ? "downloaded_file" : url.lastPathComponent
        return baseName.contains(".") ? baseName : "\(baseName).\(ext ?? "bin")"
    }
    
    func createTemporaryFile() throws -> URL {
        let fileManager = FileManager.default
        let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fileManager.createFile(atPath: destinationURL.path, contents: nil)
        return destinationURL
    }
    
    func initializeSegmentsMapIfNeeded(for url: URL, totalSegments: Int) {
        if downloadedSegmentsMap[url] == nil {
            var initialMap: [Int: Bool] = [:]
            for i in 0..<totalSegments { initialMap[i] = false }
            downloadedSegmentsMap[url] = initialMap
        }
    }
    
    func getFirstUnfinishedSegmentIndex(for url: URL, totalSegments: Int) -> Int {
        var index = 0
        while index < totalSegments && downloadedSegmentsMap[url]?[index] == true {
            index += 1
        }
        return index
    }
    
    func getDownloadedCount(for url: URL) throws -> Int {
        guard let map = downloadedSegmentsMap[url] else { return 0 }
        return map.values.filter { $0 == true }.count
    }
    
    func updateSegmentState(url: URL, index: Int, isDownloaded: Bool) {
        downloadedSegmentsMap[url]?[index] = isDownloaded
    }
    
    func notifyProgress(url: URL,
                        bytesWritten: Int64,
                        fileSize: Int64,
                        downloaded: Int,
                        total: Int,
                        active: Int) {
        let currentProgress = min(Float(downloaded) * Float(segmentSize) / Float(fileSize), 1.0)
        let remainingSegments = total - downloaded
        let currentExpectedActive = min(maxConcurrentSegments, remainingSegments)
        
        let progressModel = ProgressModel(totalSegments: total,
                                          progress: min(1.0, currentProgress),
                                          downloadedSegments: downloaded,
                                          activeSegments: active,
                                          expectedActive: currentExpectedActive)
        
        continuations[url]?.yield(.progress(progressModel))
    }
    
    func send(status: DownloadStatus, for url: URL) {
        continuations[url]?.yield(status)
    }
    
    func finishStream(for url: URL) {
        continuations[url]?.finish()
        continuations.removeValue(forKey: url)
        activeFileTasks.removeValue(forKey: url)
        activeSegmentsCountPerURL.removeValue(forKey: url)
        nextSegmentIndexPerURL.removeValue(forKey: url)
    }
    
    func downloadRangeWithTimeout(from url: URL,
                                  start: Int64,
                                  end: Int64,
                                  seconds: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            // Поток 1: Настоящий сетевой запрос куска данных
            group.addTask {
                var request = URLRequest(url: url)
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                request.timeoutInterval = seconds
                
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                request.setValue("*/*", forHTTPHeaderField: "Accept")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                
                let (data, response) = try await self.session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            // Поток 2: Таймер, который прервет группу, если сеть зависла больше чем на 10 сек
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            // Кто первый выполнился, тот и возвращает результат
            let firstResult = try await group.next()
            group.cancelAll() // Отменяем оставшийся поток (таймер или сеть)
            
            if let data = firstResult {
                return data
            } else {
                throw URLError(.unknown)
            }
        }
    }
    
    private func decrementActiveSegments(for url: URL) {
        let current = activeSegmentsCountPerURL[url] ?? 0
        activeSegmentsCountPerURL[url] = max(0, current - 1)
    }
    
    private func incrementActiveSegments(for url: URL) {
        activeSegmentsCountPerURL[url] = (activeSegmentsCountPerURL[url] ?? 0) + 1
    }
    
    private func resetNextSegmentIndex(for url: URL, to index: Int) {
        if let current = nextSegmentIndexPerURL[url], index < current {
            nextSegmentIndexPerURL[url] = index
        }
    }
}

//
//  FileDownloadActor.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 23.07.2026.
//

import Foundation

/// Downloads a single remote file using HTTP range requests and parallel segment workers.
///
/// `FileDownloadActor` owns one download session: it splits the file into fixed-size segments,
/// fetches up to `maxSegmentsPerFile` segments concurrently, writes them into a temporary file,
/// and emits progress through an `AsyncStream<DownloadStatus>`.
///
/// The actor is pause-aware. Pausing cancels the main download loop and all in-flight segment
/// tasks so no background work continues after `.pausedByRequest` is emitted.
actor FileDownloadActor {
    
    /// Remote URL of the file being downloaded.
    let url: URL
    private let metadata: (size: Int64, ext: String?)
    private var destinationURL: URL?
    private var segmentsMap: [Int: Bool] = [:]
    private var fileHandle: FileHandle?
    private var fileWriter: FileWriter?
    private var activeTasks: [Task<Void, Never>] = []
    private var downloadLoopTask: Task<Void, Never>?
    private var isPaused = false
    private var activeSegmentsCount = 0
    private var nextSegmentIndex = 0
    private var continuation: AsyncStream<DownloadStatus>.Continuation?
    
    private let maxSegmentSizeBytes: Int64
    private let maxSegmentsPerFile: Int
    private let maxRetries: Int
    private let session: URLSession
    
    /// Creates a download actor for a remote file.
    ///
    /// - Parameters:
    ///   - url: Remote file URL.
    ///   - metadata: File size in bytes and optional extension resolved from HTTP headers.
    ///   - destinationURL: Existing partial file path when resuming a saved download; `nil` for a new download.
    ///   - maxSegmentSizeBytes: Maximum byte size of each HTTP range segment.
    ///   - maxSegmentsPerFile: Maximum number of segments downloaded in parallel for this file.
    ///   - maxRetries: Number of retry attempts per failed segment.
    ///   - session: Shared `URLSession` used for range requests.
    init(url: URL,
         metadata: (size: Int64, ext: String?),
         destinationURL: URL? = nil,
         maxSegmentSizeBytes: Int64,
         maxSegmentsPerFile: Int,
         maxRetries: Int,
         session: URLSession) {
        self.url = url
        self.metadata = metadata
        self.destinationURL = destinationURL
        self.maxSegmentSizeBytes = maxSegmentSizeBytes
        self.maxSegmentsPerFile = maxSegmentsPerFile
        self.maxRetries = maxRetries
        self.session = session
    }
    
    // MARK: - Public Methods
    
    /// Starts or restarts the download and returns a stream of status updates.
    ///
    /// Calling `start()` again cancels any previous loop for this actor and attaches a new stream.
    /// The stream finishes on success, failure, or when `pause()` is called.
    ///
    /// - Returns: An `AsyncStream` that yields progress, pause, success, or failure events.
    func start() -> AsyncStream<DownloadStatus> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.isPaused = false
            self.downloadLoopTask?.cancel()
            self.activeTasks.forEach { $0.cancel() }
            self.activeTasks.removeAll()
            
            self.downloadLoopTask = Task {
                do {
                    try await self.runDownloadLoop()
                } catch is CancellationError {
                } catch {
                    if !Task.isCancelled, !self.isPaused {
                        continuation.yield(.failure(error))
                        continuation.finish()
                    }
                }
            }
        }
    }
    
    /// Pauses the download and stops all background work for this file.
    ///
    /// Cancels the main download loop, cancels in-flight segment tasks, closes the file handle,
    /// and emits `.pausedByRequest` before finishing the active stream.
    func pause() async {
        isPaused = true
        downloadLoopTask?.cancel()
        downloadLoopTask = nil
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        activeSegmentsCount = 0
        
        try? await fileWriter?.close()
        fileWriter = nil
        fileHandle = nil
        
        continuation?.yield(.pausedByRequest)
        continuation?.finish()
        continuation = nil
    }
    
    /// Returns a snapshot of persisted download progress.
    ///
    /// Used when saving application state before backgrounding or termination.
    ///
    /// - Returns: Temporary file path and indices of completed segments.
    func getState() -> (filePath: String?, downloadedSegments: [Int]) {
        (destinationURL?.path, segmentsMap.filter { $0.value }.map { $0.key })
    }
    
    /// Restores segment progress from a previously saved state.
    ///
    /// - Parameters:
    ///   - segments: Indices of segments that were already downloaded.
    ///   - filePath: Path to the existing partial file on disk.
    func restoreState(segments: [Int], filePath: String?) {
        if let filePath {
            destinationURL = URL(fileURLWithPath: filePath)
        }
        var map = [Int: Bool]()
        for idx in segments { map[idx] = true }
        self.segmentsMap = map
    }
}

// MARK: - PRIVATE EXTENSION
private extension FileDownloadActor {
    
    /// Main download scheduler.
    ///
    /// Keeps launching segment tasks until every segment is complete or the download is paused/cancelled.
    /// Respects `maxSegmentsPerFile` by tracking how many segment tasks are currently active.
    func runDownloadLoop() async throws {
        let totalSegments = Int(ceil(Double(metadata.size) / Double(maxSegmentSizeBytes)))
        if segmentsMap.isEmpty {
            for idx in 0..<totalSegments { segmentsMap[idx] = false }
        } else {
            for idx in 0..<totalSegments where segmentsMap[idx] == nil {
                segmentsMap[idx] = false
            }
        }
        if destinationURL == nil {
            destinationURL = try createTemporaryFile()
        }
        guard let destinationURL else { throw URLError(.cannotCreateFile) }
        
        let handle = try FileHandle(forWritingTo: destinationURL)
        self.fileHandle = handle
        self.fileWriter = FileWriter(handle: handle)
        defer {
            Task {
                try? await fileWriter?.close()
                fileWriter = nil
                fileHandle = nil
            }
        }
        
        nextSegmentIndex = getFirstUnfinishedSegmentIndex(totalSegments: totalSegments)
        activeSegmentsCount = 0
        
        while downloadedCount < totalSegments {
            if Task.isCancelled || isPaused { break }
            
            let active = activeSegmentsCount
            var idx = nextSegmentIndex
            
            if active < maxSegmentsPerFile && idx < totalSegments {
                while idx < totalSegments && segmentsMap[idx] == true {
                    idx += 1
                }
                guard idx < totalSegments else { continue }
                
                let segmentToDownload = idx
                nextSegmentIndex = idx + 1
                activeSegmentsCount += 1
                
                let startByte = Int64(segmentToDownload) * maxSegmentSizeBytes
                let endByte = min(startByte + maxSegmentSizeBytes - 1, metadata.size - 1)
                sendProgress(totalSegments: totalSegments)
                
                let task = Task { [weak self] in
                    guard let self else { return }
                    await self.downloadSegment(index: segmentToDownload,
                                               start: startByte,
                                               end: endByte)
                    await self.decrementActiveSegments()
                }
                activeTasks.append(task)
            }
            
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        for task in activeTasks {
            await task.value
        }
        activeTasks.removeAll()
        
        if !Task.isCancelled, !isPaused {
            try? await fileWriter?.close()
            let finalFileName = makeFileName(ext: metadata.ext)
            continuation?.yield(.success(localURL: destinationURL, fileName: finalFileName))
            continuation?.finish()
            continuation = nil
            segmentsMap.removeAll()
            self.destinationURL = nil
        }
    }
    
    /// Downloads one byte range and writes it to the destination file.
    ///
    /// Retries failed requests up to `maxRetries`. On permanent failure, emits `.failure` and stops
    /// the entire download.
    func downloadSegment(index: Int, start: Int64, end: Int64) async {
        var success = false
        var lastError: Error?
        
        for _ in 0..<maxRetries {
            if Task.isCancelled || isPaused { return }
            do {
                let data = try await downloadRangeWithTimeout(start: start, end: end, seconds: 10)
                if Task.isCancelled || isPaused { return }
                try await fileWriter?.write(data: data, at: UInt64(start))
                segmentsMap[index] = true
                success = true
                break
            } catch {
                if Task.isCancelled { return }
                lastError = error
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        
        let total = Int(ceil(Double(metadata.size) / Double(maxSegmentSizeBytes)))
        
        if success {
            sendProgress(totalSegments: total)
        } else {
            if let lastError {
                if index < nextSegmentIndex {
                    nextSegmentIndex = index
                }
                sendProgress(totalSegments: total)
                try? await Task.sleep(nanoseconds: 800_000_000)
                
                continuation?.yield(.failure(lastError))
                try? await fileWriter?.close()
                fileWriter = nil
                fileHandle = nil
                continuation?.finish()
                continuation = nil
                
                activeTasks.forEach { $0.cancel() }
                activeTasks.removeAll()
            }
        }
    }
    
    // MARK: Helpers
    
    /// Emits a progress snapshot to the active stream consumer.
    func sendProgress(totalSegments: Int) {
        let downloaded = downloadedCount
        let downloadedBytes = calculateDownloadedBytes(fileSize: metadata.size)
        let progress = Float(downloadedBytes) / Float(metadata.size)
        let remaining = totalSegments - downloaded
        let expectedActive = min(maxSegmentsPerFile, remaining)
        
        let model = ProgressModel(
            totalSegments: totalSegments,
            progress: min(1.0, progress),
            downloadedSegments: downloaded,
            activeSegments: activeSegmentsCount,
            expectedActive: expectedActive
        )
        continuation?.yield(.progress(model))
    }
    
    var downloadedCount: Int {
        segmentsMap.values.filter { $0 }.count
    }
    
    func getFirstUnfinishedSegmentIndex(totalSegments: Int) -> Int {
        var idx = 0
        while idx < totalSegments && segmentsMap[idx] == true { idx += 1 }
        return idx
    }
    
    func calculateDownloadedBytes(fileSize: Int64) -> Int64 {
        var bytes: Int64 = 0
        for (index, downloaded) in segmentsMap where downloaded {
            let start = Int64(index) * maxSegmentSizeBytes
            let end = min(start + maxSegmentSizeBytes - 1, fileSize - 1)
            bytes += end - start + 1
        }
        return bytes
    }
    
    func createTemporaryFile() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        return tempURL
    }
    
    func makeFileName(ext: String?) -> String {
        let baseName = url.lastPathComponent.isEmpty ? "downloaded_file" : url.lastPathComponent
        return baseName.contains(".") ? baseName : "\(baseName).\(ext ?? "bin")"
    }
    
    /// Performs one HTTP range request with a hard timeout.
    ///
    /// Uses a racing task group so a slow network call cannot block the segment worker indefinitely.
    func downloadRangeWithTimeout(start: Int64, end: Int64, seconds: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                var request = URLRequest(url: self.url)
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                request.timeoutInterval = seconds
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                request.setValue("*/*", forHTTPHeaderField: "Accept")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                
                let (data, response) = try await self.session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 206,
                      httpResponse.value(forHTTPHeaderField: "Content-Range") != nil else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            let result = try await group.next()
            group.cancelAll()
            if let data = result {
                return data
            } else {
                throw URLError(.unknown)
            }
        }
    }
    
    func decrementActiveSegments() {
        activeSegmentsCount = max(0, activeSegmentsCount - 1)
    }
}

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

/// Events emitted while a file download is running.
enum DownloadStatus {
    /// Partial progress update for UI rendering.
    case progress(ProgressModel)
    /// Download was paused manually or because the concurrent-files limit was reached.
    case pausedByRequest
    /// Download finished successfully.
    case success(localURL: URL, fileName: String?)
    /// Download failed and cannot continue without user action.
    case failure(Error)
}

/// Coordinates multiple file downloads and enforces concurrency limits.
///
/// `DownloadNetworkManager` is the entry point for the download feature. It:
/// - fetches remote metadata and creates one `FileDownloadActor` per URL;
/// - keeps at most `maxConcurrentFiles` downloads active at the same time;
/// - puts excess downloads on pause instead of keeping them in a waiting queue;
/// - preempts the most recently started active download when a paused download is resumed at capacity.
///
/// Download actors are stored in three buckets:
/// - `activeDownloads` — currently downloading;
/// - `pausedDownloads` — created or paused and waiting for user resume;
/// - `pendingActors` — metadata fetched but not yet activated.
actor DownloadNetworkManager {
    
    private let defaultMaxSegments = 5
    private let defaultMaxSegmentSizeMB = 5
    private let defaultMaxConcurrentFiles = 3
    private let defaultRetryAttempts = 3
    
    private var activeDownloads: [URL: FileDownloadActor] = [:]
    private var activeDownloadOrder: [URL] = []
    private var pausedDownloads: [URL: FileDownloadActor] = [:]
    private var pendingActors: [URL: FileDownloadActor] = [:]
    
    // MARK: - Dynamic settings
    private var maxSegmentsPerFile: Int {
        UserDefaults.standard.integer(forKey: "maxSegmentsPerFile")
    }
    
    private var maxSegmentSizeBytes: Int64 {
        let mb = UserDefaults.standard.integer(forKey: "maxSegmentSizeMB")
        let safeMB = mb > 0 ? mb : 5
        return Int64(safeMB) * 1024 * 1024
    }
    
    private var maxConcurrentFilesLimit: Int {
        let value = UserDefaults.standard.integer(forKey: "maxConcurrentFiles")
        return value > 0 ? value : defaultMaxConcurrentFiles
    }
    
    private var maxRetries: Int {
        UserDefaults.standard.integer(forKey: "retryAttempts")
    }
    
    private var session: URLSession
    private let metadataService: FileMetadataService
    
    /// Creates the manager and registers default download settings in `UserDefaults`.
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 10
        self.session = URLSession(configuration: configuration)
        self.metadataService = FileMetadataService(session: session)
        Task {
            await registerDefaultSettings()
        }
    }
    
    // MARK: - Public API
    
    /// Starts a new download or returns the current stream for an existing one.
    ///
    /// Behavior by state:
    /// - paused: returns a stream that immediately emits `.pausedByRequest` without starting work;
    /// - active: returns a fresh stream from the running actor;
    /// - pending/new: activates immediately when capacity is available, otherwise stores the actor as paused.
    ///
    /// - Parameter urlString: Remote file URL.
    /// - Returns: Stream of download status updates.
    func downloadFile(from urlString: String) async throws -> AsyncStream<DownloadStatus> {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        guard pausedDownloads[url] == nil else { return makePausedStream() }
        if let actor = activeDownloads[url] {
            return await actor.start()
        }
        if let actor = pendingActors[url] {
            return await activateOrPause(actor: actor, url: url)
        }
        
        let metadata = try await metadataService.fetchMetadata(from: url)
        let actor = FileDownloadActor(
            url: url,
            metadata: metadata,
            maxSegmentSizeBytes: maxSegmentSizeBytes,
            maxSegmentsPerFile: maxSegmentsPerFile,
            maxRetries: maxRetries,
            session: session
        )
        pendingActors[url] = actor
        return await activateOrPause(actor: actor, url: url)
    }
    
    /// Resumes a paused download and preempts another active download when at capacity.
    ///
    /// If the concurrent-files limit is already reached, the most recently started active download
    /// is paused and the requested download takes its slot.
    ///
    /// - Parameter urlString: Remote file URL.
    /// - Returns: Stream of download status updates for the resumed download.
    func resumeDownload(for urlString: String) async throws -> AsyncStream<DownloadStatus> {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        if let actor = activeDownloads[url] {
            return await actor.start()
        }
        if let actor = pausedDownloads[url] {
            pausedDownloads.removeValue(forKey: url)
            return await resumeDownload(actor: actor, url: url)
        }
        if let actor = pendingActors[url] {
            return await resumeDownload(actor: actor, url: url)
        }
        return try await downloadFile(from: urlString)
    }
    
    /// Pauses an active download or moves a not-yet-started download into the paused bucket.
    ///
    /// - Parameter urlString: Remote file URL.
    func pauseDownload(for urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        if let actor = activeDownloads[url] {
            activeDownloads.removeValue(forKey: url)
            removeFromActiveOrder(url)
            await actor.pause()
            pausedDownloads[url] = actor
        } else if let actor = pendingActors[url] {
            pendingActors.removeValue(forKey: url)
            pausedDownloads[url] = actor
        }
    }
    
    /// Fetches the remote file extension without starting a download.
    func fetchFileExtension(from urlString: String) async throws -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let metadata = try await metadataService.fetchMetadata(from: url)
        return metadata.ext
    }
    
    // MARK: - Persistence
    
    /// Serializes active and paused downloads so they can be restored after app restart.
    func saveState() async throws -> Data {
        var state: [[String: Any]] = []
        
        for (url, actor) in activeDownloads {
            let actorState = await actor.getState()
            guard let path = actorState.filePath else { continue }
            let dict: [String: Any] = [
                "url": url.absoluteString,
                "filePath": path,
                "downloadedSegments": actorState.downloadedSegments
            ]
            state.append(dict)
        }
        
        for (url, actor) in pausedDownloads {
            let actorState = await actor.getState()
            guard let path = actorState.filePath else { continue }
            let dict: [String: Any] = [
                "url": url.absoluteString,
                "filePath": path,
                "downloadedSegments": actorState.downloadedSegments
            ]
            state.append(dict)
        }
        
        return try JSONSerialization.data(withJSONObject: state, options: .prettyPrinted)
    }
    
    /// Restores paused downloads from serialized state.
    ///
    /// Restored actors are placed into `pausedDownloads` and must be resumed explicitly by the UI.
    ///
    /// - Parameter data: JSON produced by `saveState()`.
    /// - Returns: URLs that were successfully restored.
    func loadState(from data: Data) async -> [URL] {
        var restoredURLs: [URL] = []
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return restoredURLs }
        
        for item in array {
            guard let urlString = item["url"] as? String,
                  let url = URL(string: urlString),
                  let filePath = item["filePath"] as? String,
                  let segments = item["downloadedSegments"] as? [Int]
            else { continue }
            
            let fileURL = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            
            guard let metadata = try? await metadataService.fetchMetadata(from: url) else { continue }
            
            let actor = FileDownloadActor(
                url: url,
                metadata: metadata,
                destinationURL: fileURL,
                maxSegmentSizeBytes: maxSegmentSizeBytes,
                maxSegmentsPerFile: maxSegmentsPerFile,
                maxRetries: maxRetries,
                session: session
            )
            await actor.restoreState(segments: segments, filePath: filePath)
            pausedDownloads[url] = actor
            restoredURLs.append(url)
        }
        return restoredURLs
    }
    
}

// MARK: - PRIVATE METHODS
private extension DownloadNetworkManager {
    
    /// Activates a download immediately or stores it as paused when the concurrent limit is reached.
    func activateOrPause(actor: FileDownloadActor, url: URL) async -> AsyncStream<DownloadStatus> {
        if activeDownloads.count < maxConcurrentFilesLimit {
            return await activateNow(actor: actor, url: url)
        }
        pendingActors.removeValue(forKey: url)
        pausedDownloads[url] = actor
        return makePausedStream()
    }
    
    /// Starts a paused/pending actor, preempting another download when necessary.
    func resumeDownload(actor: FileDownloadActor, url: URL) async -> AsyncStream<DownloadStatus> {
        if activeDownloads.count >= maxConcurrentFilesLimit {
            await preemptLastActiveDownload(excluding: url)
        }
        return await activateNow(actor: actor, url: url)
    }
    
    /// Moves an actor into the active set and wraps its stream with lifecycle handling.
    func activateNow(actor: FileDownloadActor, url: URL) async -> AsyncStream<DownloadStatus> {
        pendingActors.removeValue(forKey: url)
        activeDownloads[url] = actor
        activeDownloadOrder.append(url)
        let rawStream = await actor.start()
        return makeWrappedStream(url: url, rawStream: rawStream)
    }
    
    /// Pauses the most recently started active download to free a slot for another URL.
    func preemptLastActiveDownload(excluding excludedURL: URL) async {
        guard let victimURL = activeDownloadOrder.last(where: { $0 != excludedURL }),
              let victimActor = activeDownloads[victimURL] else { return }
        activeDownloads.removeValue(forKey: victimURL)
        removeFromActiveOrder(victimURL)
        await victimActor.pause()
        pausedDownloads[victimURL] = victimActor
    }
    
    /// Creates a stream that reports a paused state without starting network work.
    func makePausedStream() -> AsyncStream<DownloadStatus> {
        AsyncStream { continuation in
            continuation.yield(.pausedByRequest)
            continuation.finish()
        }
    }
    
    func removeFromActiveOrder(_ url: URL) {
        activeDownloadOrder.removeAll { $0 == url }
    }
    
    /// Forwards actor events to the caller and performs cleanup when the stream finishes.
    func makeWrappedStream(url: URL, rawStream: AsyncStream<DownloadStatus>) -> AsyncStream<DownloadStatus> {
        AsyncStream { continuation in
            let task = Task {
                for await status in rawStream {
                    continuation.yield(status)
                }
                await self.handleDownloadCompletion(url: url)
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// Removes bookkeeping entries after a download stream completes.
    func handleDownloadCompletion(url: URL) async {
        if activeDownloads[url] != nil {
            activeDownloads.removeValue(forKey: url)
            removeFromActiveOrder(url)
        }
        pendingActors[url] = nil
    }
    
    /// Registers fallback values for user-configurable download settings.
    func registerDefaultSettings() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "maxSegmentsPerFile": defaultMaxSegments,
            "maxSegmentSizeMB": defaultMaxSegmentSizeMB,
            "maxConcurrentFiles": defaultMaxConcurrentFiles,
            "retryAttempts": defaultRetryAttempts
        ])
    }
}

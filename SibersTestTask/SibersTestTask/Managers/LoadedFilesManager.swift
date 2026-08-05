//
//  LoadedFilesManager.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 18.07.2026.
//

import Foundation

protocol LoadedFilesManagerProtocol: AnyObject {
    
    var delegate: LoadedFilesManagerDelegate? { get set }
    func addToTheDocumentDirectory(temporaryUrl: URL, fileName: String?) throws
    func fetchDownloadedFiles() throws -> [URL]
}

protocol LoadedFilesManagerDelegate: AnyObject {
    func loadedFilesManagerDirectoryUpdated(_ manager: LoadedFilesManager, fileUrls: [URL])
}

final class LoadedFilesManager: LoadedFilesManagerProtocol {
    
    weak var delegate: LoadedFilesManagerDelegate?{
        didSet {
            updateDelegateChanges()
            startMonitoringFilesChanges()
        }
    }
    
    // Files monitoring
    private var fileSystemSource: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.sibers.loadedfilesmanager.monitor", qos: .utility)
    
    private let fileManager = FileManager.default
    private let folderName = "SibersDownloadedFiles"
    
    private var downloadsFolderURL: URL? {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folderURL = documentsURL.appendingPathComponent(folderName, isDirectory: true)
        
        if !fileManager.fileExists(atPath: folderURL.path(percentEncoded: false)) {
            do {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Ошибка создания директории: \(error)")
                return nil
            }
        }
        return folderURL
    }
    
    deinit {
        stopMonitoring()
    }
    
    func addToTheDocumentDirectory(temporaryUrl: URL, fileName: String?) throws {
        guard let folderURL = downloadsFolderURL else { throw URLError(.cannotCreateFile) }
        
        let fileName = fileName ?? temporaryUrl.lastPathComponent
        let destinationURL = folderURL.appendingPathComponent(fileName)
        
        let destPath = destinationURL.path(percentEncoded: false)
        if fileManager.fileExists(atPath: destPath) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.moveItem(at: temporaryUrl, to: destinationURL)
        
        updateDelegateChanges()
    }
    
    func fetchDownloadedFiles() throws -> [URL] {
        guard let folderURL = downloadsFolderURL else { return [] }
        let fileURLs = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        return fileURLs
    }
}

// MARK: - PRIVATE METHODS
private extension LoadedFilesManager {
    
    private func updateDelegateChanges() {
        let fileUrls = (try? self.fetchDownloadedFiles()) ?? []
        DispatchQueue.main.async {
            self.delegate?.loadedFilesManagerDirectoryUpdated(self, fileUrls: fileUrls)
        }
    }
    
    private func startMonitoringFilesChanges() {
        guard fileSystemSource == nil, let folderURL = downloadsFolderURL else { return }
        
        // Открываем дескриптор папки (нужен только для чтения O_RDONLY)
        directoryFileDescriptor = open(folderURL.path(percentEncoded: false), O_RDONLY)
        guard directoryFileDescriptor != -1 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: .write,
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            updateDelegateChanges()
        }
        
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.directoryFileDescriptor)
            self.directoryFileDescriptor = -1
        }
        
        self.fileSystemSource = source
        source.resume()
    }
    
    private func stopMonitoring() {
        fileSystemSource?.cancel()
        fileSystemSource = nil
    }
    
}

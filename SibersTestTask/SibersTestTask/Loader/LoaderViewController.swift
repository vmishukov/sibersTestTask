//
//  ViewController.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 17.07.2026.
//

import UIKit

final class LoaderViewController: UIViewController {
    
    private var linkTextFiled: UITextField = {
        let textField = UITextField()
        textField.keyboardType = .URL
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.clearButtonMode = .whileEditing
        textField.placeholder = "https://example.com/file.pdf"
        let iconView = UIImageView(image: UIImage(systemName: "link"))
        iconView.tintColor = .systemGray
        iconView.contentMode = .center
        textField.returnKeyType = .done
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        iconView.frame = CGRect(x: 10, y: 0, width: 20, height: 20)
        paddingView.addSubview(iconView)
        
        textField.leftView = paddingView
        textField.leftViewMode = .always
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.backgroundColor = .systemGray6
        textField.layer.cornerRadius = 16
        return textField
    }()
    
    private var downloadButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        var container = AttributeContainer()
        container.font = .systemFont(ofSize: 18, weight: .semibold)
        configuration.attributedTitle = AttributedString("Download", attributes: container)
        let originalImage = UIImage(resource: .downloadIcon)
        configuration.image = originalImage.resized(to: CGSize(width: 30, height: 30))
        configuration.imagePadding = 4
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .systemBlue
        button.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        return button
    }()
    
    private var downloadTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(LoaderTableViewCell.self, forCellReuseIdentifier: LoaderTableViewCell.identifier)
        tableView.allowsSelection = false
        return tableView
    }()
    
    private var downloadManager = DownloadNetworkManager()
    private var loadedFilesManager: LoadedFilesManager
    private var downloads: [DownloadItem] = []
    
    init(loadedFilesManager: LoadedFilesManager) {
        self.loadedFilesManager = loadedFilesManager
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupUi()
        setupConstraints()
        setupBackgroundObservers()
        restoreDownloadsIfNeeded()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - PRIVATE METHODS
private extension LoaderViewController {
    
    func setupNavigationBar() {
        navigationItem.title = "Loader"
        
        let settingsButton = UIBarButtonItem(title: "settings",
                                             style: .plain,
                                             target: self,
                                             action: #selector(presentSettingsController))
        settingsButton.image = UIImage(systemName: "gearshape")
        navigationItem.rightBarButtonItems = [settingsButton]
    }
    
    func setupUi() {
        view.addSubview(linkTextFiled)
        view.addSubview(downloadButton)
        view.addSubview(downloadTableView)
        linkTextFiled.delegate = self
        downloadTableView.dataSource = self
        downloadTableView.delegate = self
        view.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                         action: #selector(hideKeyboard)))
        downloadButton.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            linkTextFiled.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            linkTextFiled.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            linkTextFiled.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            linkTextFiled.heightAnchor.constraint(equalToConstant: 50),
            downloadButton.topAnchor.constraint(equalTo: linkTextFiled.bottomAnchor, constant: 16),
            downloadButton.leadingAnchor.constraint(equalTo: linkTextFiled.leadingAnchor),
            downloadButton.trailingAnchor.constraint(equalTo: linkTextFiled.trailingAnchor),
            downloadButton.heightAnchor.constraint(equalToConstant: 50),
            downloadTableView.topAnchor.constraint(equalTo: downloadButton.bottomAnchor, constant: 16),
            downloadTableView.leadingAnchor.constraint(equalTo: downloadButton.leadingAnchor),
            downloadTableView.trailingAnchor.constraint(equalTo: downloadButton.trailingAnchor),
            downloadTableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)
        ])
    }
    
    @objc
    func hideKeyboard() {
        view.endEditing(true)
    }
    
    @objc
    func presentSettingsController() {
        let settingsController = SettingsViewController()
        settingsController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(settingsController, animated: true)
    }
    
    @objc
    func downloadButtonTapped() {
        guard let textUrl = linkTextFiled.text else { return }
        guard !downloads.contains(where: { $0.url == textUrl }) else {
            return showErrorAlert(with: "File already loading")
        }
        addDownloadModel(textUrl: textUrl, fethedExtension: nil)
        downloadButton.isEnabled = true
        addLoadTask(textUrl: textUrl)
    }
    
    func addLoadTask(textUrl: String) {
        Task {
            do {
                let stream = try await downloadManager.downloadFile(from: textUrl)
                let fetchedExtension = try await downloadManager.fetchFileExtension(from: textUrl)
                
                await MainActor.run {
                    if let index = downloads.firstIndex(where: { $0.url == textUrl }) {
                        var name = URL(string: textUrl)?.lastPathComponent ?? "Скачиваемый файл"
                        if !name.contains("."), let ext = fetchedExtension {
                            name = "\(name).\(ext)"
                        }
                        downloads[index].title = name
                        
                        let indexPath = IndexPath(row: index, section: 0)
                        if let cell = downloadTableView.cellForRow(at: indexPath) as? LoaderTableViewCell {
                            cell.setupCell(with: downloads[index])
                        }
                    }
                }
                try await downloadFileWithProgress(stream: stream, textUrl: textUrl)
                
            } catch {
                await MainActor.run {
                    downloads.removeAll(where: { $0.url == textUrl })
                    downloadTableView.reloadData()
                    showErrorAlert(with: error.localizedDescription)
                }
            }
        }
    }
    
    func addDownloadModel(textUrl: String, fethedExtension: String?) {
        var proposedName = URL(string: textUrl)?.lastPathComponent ?? "Скачиваемый файл"
        if !proposedName.contains("."), let ext = fethedExtension {
            proposedName = "\(proposedName).\(ext)"
        }
        
        let newDownload = DownloadItem(
            url: textUrl,
            title: proposedName,
            progress: ProgressModel(totalSegments: 5)
        )
        downloads.append(newDownload)
        
        let indexPath = IndexPath(row: downloads.count - 1, section: 0)
        downloadTableView.insertRows(at: [indexPath], with: .automatic)
        
        if let cell = downloadTableView.cellForRow(at: indexPath) as? LoaderTableViewCell {
            cell.setupCell(with: newDownload)
            cell.pauseContinueButton.isEnabled = true
        }
    }
    
    func downloadFileWithProgress(
        stream: AsyncStream<DownloadStatus>,
        textUrl: String
    ) async throws {
        for await status in stream {
            switch status {
            case .progress(let progress):
                await MainActor.run {
                    updateTableCell(for: textUrl, with: progress)
                }
                
            case .success(let localURL, let fileName):
                try loadedFilesManager.addToTheDocumentDirectory(
                    temporaryUrl: localURL,
                    fileName: fileName
                )
                await MainActor.run {
                    downloads.removeAll(where: { $0.url == textUrl })
                    downloadTableView.reloadData()
                }
                
            case .failure(let error):
                await MainActor.run {
                    downloads.removeAll(where: { $0.url == textUrl })
                    downloadTableView.reloadData()
                }
                throw error
                
            case .pausedByRequest:
                await MainActor.run {
                    if let index = downloads.firstIndex(where: { $0.url == textUrl }) {
                        downloads[index].state = .paused
                        let indexPath = IndexPath(row: index, section: 0)
                        if let cell = downloadTableView.cellForRow(at: indexPath) as? LoaderTableViewCell {
                            cell.configureAsPaused()
                        }
                    }
                }
                return
            }
        }
    }
    
    func updateTableCell(for textUrl: String, with progress: ProgressModel) {
        guard let index = downloads.firstIndex(where: { $0.url == textUrl }) else { return }
        downloads[index].progress = progress
        
        let indexPath = IndexPath(row: index, section: 0)
        guard let cell = downloadTableView.cellForRow(at: indexPath) as? LoaderTableViewCell else {
            return
        }
        cell.updateProgress(progress)
        if downloads[index].state != .downloading {
            downloads[index].state = .downloading
            cell.setPauseStatus(false)
            cell.pauseContinueButton.isEnabled = true
        }
    }
    
    func showErrorAlert(with message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    func restoreDownloadsIfNeeded() {
        Task {
            let stateURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("downloadState.json")
            guard let data = try? Data(contentsOf: stateURL) else { return }
            
            let restoredURLs = await downloadManager.loadState(from: data)
            for url in restoredURLs {
                let urlString = url.absoluteString
                addLoadTask(textUrl: urlString)
            }
            try? FileManager.default.removeItem(at: stateURL)
        }
    }
    
    @objc
    private func appDidEnterBackground() {
        final class TaskID { var value: UIBackgroundTaskIdentifier = .invalid }
        let taskID = TaskID()
        
        taskID.value = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(taskID.value)
        }
        
        Task {
            if let stateData = try? await downloadManager.saveState() {
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("downloadState.json")
                try? stateData.write(to: url)
            }
            UIApplication.shared.endBackgroundTask(taskID.value)
        }
    }
    
    private func setupBackgroundObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
}

// MARK: - UITableViewDataSource
extension LoaderViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        downloads.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellRow = tableView.dequeueReusableCell(withIdentifier: LoaderTableViewCell.identifier, for: indexPath)
        guard
            let loaderCell = cellRow as? LoaderTableViewCell,
            let itemModel = downloads[safe: indexPath.row]
        else {
            return cellRow
        }
        
        loaderCell.setupCell(with: itemModel)

        loaderCell.pauseContinueAction = { [weak self] in
            guard let self, let currentItem = self.downloads[safe: indexPath.row] else { return }
            Task {
                switch currentItem.state {
                case .downloading:
                    await MainActor.run {
                        if let idx = self.downloads.firstIndex(where: { $0.url == currentItem.url }) {
                            self.downloads[idx].state = .paused
                            let ip = IndexPath(row: idx, section: 0)
                            if let cell = self.downloadTableView.cellForRow(at: ip) as? LoaderTableViewCell {
                                cell.configureAsPaused()
                            }
                        }
                    }
                    await self.downloadManager.pauseDownload(for: currentItem.url)
                case .waiting, .paused:
                    do {
                        let stream = try await self.downloadManager.resumeDownload(for: currentItem.url)
                        await MainActor.run {
                            if let idx = self.downloads.firstIndex(where: { $0.url == currentItem.url }) {
                                self.downloads[idx].state = .downloading
                                let ip = IndexPath(row: idx, section: 0)
                                if let cell = self.downloadTableView.cellForRow(at: ip) as? LoaderTableViewCell {
                                    cell.configureAsDownloading()
                                }
                            }
                        }
                        try await self.downloadFileWithProgress(stream: stream, textUrl: currentItem.url)
                    } catch {
                        await MainActor.run { self.showErrorAlert(with: error.localizedDescription) }
                    }
                }
            }
        }
        return loaderCell
    }
}

// MARK: - UITableViewDelegate
extension LoaderViewController: UITableViewDelegate {}

// MARK: - UITextFieldDelegate
extension LoaderViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

#Preview {
    LoaderViewController(loadedFilesManager: LoadedFilesManager())
}

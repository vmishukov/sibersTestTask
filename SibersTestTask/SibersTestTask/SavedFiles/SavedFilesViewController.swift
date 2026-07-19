//
//  SavedFilesViewController.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 17.07.2026.
//

import UIKit

final class SavedFilesViewController: UIViewController {
    
    private var savedFilesTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(SavedFilesTableViewCell.self,
                           forCellReuseIdentifier: SavedFilesTableViewCell.identifier)
        return tableView
    }()
    
    var savedFiles: [URL] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupUi()
        setupConstraints()
    }
    
}

// MARK: - PRIVATE METHODS
private extension SavedFilesViewController {
    
    func setupUi() {
        savedFilesTableView.delegate = self
        savedFilesTableView.dataSource = self
        view.addSubview(savedFilesTableView)
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            savedFilesTableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            savedFilesTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            savedFilesTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            savedFilesTableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
    }
    
    func setupNavigationBar() {
        navigationItem.title = "Saved files"
    }
}

// MARK: - UITableViewDelegate
extension SavedFilesViewController: UITableViewDelegate {
    
}

// MARK: - UITableViewDataSource
extension SavedFilesViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        savedFiles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SavedFilesTableViewCell.identifier, for: indexPath)
        guard let fileCell = cell as? SavedFilesTableViewCell else { return cell }
        fileCell.configure(with: savedFiles[indexPath.row].absoluteString)
        return fileCell
    }
    
}

// MARK: - LoadedFilesManagerDelegate
extension SavedFilesViewController: LoadedFilesManagerDelegate {
    
    func loadedFilesManagerDirectoryUpdated(_ manager: LoadedFilesManager, fileUrls: [URL]) {
        savedFiles = fileUrls
        savedFilesTableView.reloadData()
    }
    
}

#Preview {
    SavedFilesViewController()
}

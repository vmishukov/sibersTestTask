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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupUi()
        setupConstraints()
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
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            linkTextFiled.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            linkTextFiled.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            linkTextFiled.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
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
}

// MARK: - UITableViewDataSource
extension LoaderViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        2
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellRow = tableView.dequeueReusableCell(withIdentifier: LoaderTableViewCell.identifier, for: indexPath)
        guard let loaderCell = cellRow as? LoaderTableViewCell else {
            return cellRow
        }
        
        if indexPath.row == 1 {
            loaderCell.setupCell(with: "Kill Bill.mp4", and: "https://www.youtube.com/watch?v=KjDArqWy-xU")
        }
        
        return loaderCell
    }
    
}

// MARK: - UITableViewDelegate
extension LoaderViewController: UITableViewDelegate {
    
}

// MARK: - UITextFieldDelegate
extension LoaderViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

#Preview {
    LoaderViewController()
}

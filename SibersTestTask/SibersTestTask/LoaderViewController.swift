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
        linkTextFiled.delegate = self
        view.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                         action: #selector(hideKeyboard)))
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            linkTextFiled.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            linkTextFiled.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            linkTextFiled.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            linkTextFiled.heightAnchor.constraint(equalToConstant: 50)
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

//
//  SettingsViewController.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 17.07.2026.
//

import UIKit

final class SettingsViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupUi()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
}

// MARK: - PRIVATE METHODS
private extension SettingsViewController {
    
    func setupNavigationBar() {
        title = "Settings"
    }
    
    func setupUi() {
        
    }
    
}

#Preview {
    SettingsViewController()
}

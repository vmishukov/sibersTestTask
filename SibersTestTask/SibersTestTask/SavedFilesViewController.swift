//
//  SavedFilesViewController.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 17.07.2026.
//

import UIKit

final class SavedFilesViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .blue
        setupNavigationBar()
    }
    
}

private extension SavedFilesViewController {
    
    func setupNavigationBar() {
        navigationItem.title = "Saved files"
    }
}

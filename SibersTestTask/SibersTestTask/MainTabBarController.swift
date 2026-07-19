//
//  MainTabBarController.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 17.07.2026.
//

import UIKit

final class MainTabBarController: UITabBarController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
    }
    
}

// MARK: - PRIVATE METHODS
private extension MainTabBarController {
    
    func setupTabs() {
        let savedFilesViewController = SavedFilesViewController()
        let loadedFilesManager = LoadedFilesManager()
        loadedFilesManager.delegate = savedFilesViewController
        let loaderViewController = LoaderViewController(loadedFilesManager: loadedFilesManager)
        
        loaderViewController.tabBarItem = UITabBarItem(title: "Loader", image: UIImage(systemName: "square.and.arrow.up"), tag: 0)
        savedFilesViewController.tabBarItem = UITabBarItem(title: "Saved", image: UIImage(systemName: "square.and.arrow.down"), tag: 1)
        
        let loaderNavigationController = UINavigationController(rootViewController: loaderViewController)
        let savedFilesNavigationController = UINavigationController(rootViewController: savedFilesViewController)
        
        viewControllers = [loaderNavigationController, savedFilesNavigationController]
    }
}

#Preview {
    MainTabBarController()
}

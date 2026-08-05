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
        
        let loaderViewController = assembleLoaderViewController(with: savedFilesViewController)
        loaderViewController.tabBarItem = UITabBarItem(title: "Loader", image: UIImage(systemName: "square.and.arrow.up"), tag: 0)
        savedFilesViewController.tabBarItem = UITabBarItem(title: "Saved", image: UIImage(systemName: "square.and.arrow.down"), tag: 1)
        
        let loaderNavigationController = UINavigationController(rootViewController: loaderViewController)
        let savedFilesNavigationController = UINavigationController(rootViewController: savedFilesViewController)
        
        viewControllers = [loaderNavigationController, savedFilesNavigationController]
    }
    
    func assembleLoaderViewController(with delegate: LoadedFilesManagerDelegate) -> UIViewController {
        let loadedFilesManager = LoadedFilesManager()
        loadedFilesManager.delegate = delegate
        let downloadManager = DownloadNetworkManager()
        let loaderViewController = LoaderViewController(downloadManager: downloadManager,
                                                        loadedFilesManager: loadedFilesManager)
        return loaderViewController
    }
}

#Preview {
    MainTabBarController()
}

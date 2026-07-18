//
//  Extensions.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 18.07.2026.
//

import UIKit

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        
        let resizedImage = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
        return resizedImage.withRenderingMode(self.renderingMode)
    }
}

//
//  SavedFilesTableViewCell.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 18.07.2026.
//

import UIKit

final class SavedFilesTableViewCell: UITableViewCell {
    
    static let identifier = String(describing: SavedFilesTableViewCell.self)
    
    private var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "test.mp4"
        label.numberOfLines = 0
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        initialSetup()
        setupConstraints()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SavedFilesTableViewCell {
    
    func configure(with title: String) {
        titleLabel.text = title
    }
}

// MARK: - PRIVATE EXTENSION
private extension SavedFilesTableViewCell {
    
    func initialSetup() {
        contentView.addSubview(titleLabel)
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
}

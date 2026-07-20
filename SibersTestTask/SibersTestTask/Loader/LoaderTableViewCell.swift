//
//  LoaderTableViewCell.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 18.07.2026.
//

import UIKit

final class LoaderTableViewCell: UITableViewCell {
    
    static let identifier = String(describing: LoaderTableViewCell.self)
    
    private var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "DeadPool 2016.MP4"
        return label
    }()
    
    private var urlLaberl: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "https://www.youtube.com/watch?v=oIAMxQ1KLiI"
        label.font = .systemFont(ofSize: 12, weight: .light)
        label.textColor = .systemGray
        label.numberOfLines = 0
        return label
    }()
    
    private var progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .white
        progressView.progressTintColor = .green
        progressView.progress = 0.5
        return progressView
    }()
    
    private var pauseContinueButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "pause")
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .systemMint
        return button
    }()
    
    private var infoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Total downloaded: 12/30 Active: 3/5"
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textAlignment = .left
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

// MARK: - PUBLIC METHODS
extension LoaderTableViewCell {
    
    func setupCell(with model: DownloadItem) {
        titleLabel.text = model.title
        urlLaberl.text = model.url
        progressView.progress = model.progress
    }
    
}

// MARK: - PRIVATE METHODS
private extension LoaderTableViewCell {
    
    func initialSetup() {
        contentView.addSubview(progressView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(urlLaberl)
        contentView.addSubview(pauseContinueButton)
        contentView.addSubview(infoLabel)
        pauseContinueButton.addTarget(self, action: #selector(pauseContinueButtonDidTap), for: .touchUpInside)
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.centerXAnchor),
            urlLaberl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            urlLaberl.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            urlLaberl.trailingAnchor.constraint(equalTo: contentView.centerXAnchor),
            urlLaberl.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -4),
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            pauseContinueButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            pauseContinueButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            pauseContinueButton.heightAnchor.constraint(equalToConstant: 50),
            pauseContinueButton.widthAnchor.constraint(equalToConstant: 50),
            infoLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            infoLabel.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 4),
            infoLabel.trailingAnchor.constraint(equalTo: pauseContinueButton.leadingAnchor, constant: -4),
            infoLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    @objc
    func pauseContinueButtonDidTap() {
        pauseContinueButton.configuration?.image = UIImage(systemName: "play.fill")
    }
}

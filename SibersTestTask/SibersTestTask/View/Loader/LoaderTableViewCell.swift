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
        return label
    }()
    
    private var urlLaberl: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 9, weight: .light)
        label.textColor = .systemGray
        label.numberOfLines = 4
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
    
    private(set) var pauseContinueButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "pause.fill")
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
    
    var pauseContinueAction: (() -> Void)?
    
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
    
    func setPauseStatus(_ isPaused: Bool) {
        let playImage = UIImage(systemName: "play.fill")
        let pauseImage = UIImage(systemName: "pause.fill")
        pauseContinueButton.configuration?.image = isPaused ? playImage : pauseImage
        pauseContinueButton.isEnabled = true
    }
    
    func updateProgress(_ progress: ProgressModel) {
        progressView.progress = progress.progress
        infoLabel.text = "Total downloaded: \(progress.downloadedSegments)/\(progress.totalSegments) Active: \(progress.activeSegments)/\(progress.expectedActive)"
    }
    
    func setupCell(with model: DownloadItem) {
        titleLabel.text = model.title
        updateProgress(model.progress)
        urlLaberl.text = model.url
        switch model.state {
        case .waiting:
            infoLabel.text = "In Queue..."
            setPauseStatus(true)
            pauseContinueButton.isEnabled = true
            
        case .downloading:
            setPauseStatus(false)
            pauseContinueButton.isEnabled = true
            
        case .paused:
            infoLabel.text = "Paused"
            setPauseStatus(true)
            pauseContinueButton.isEnabled = true
        }
    }
    
    func configureAsDownloading() {
        infoLabel.text = nil
        pauseContinueButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseContinueButton.isEnabled = true
    }
    
    func configureAsPaused() {
        infoLabel.text = "Paused"
        pauseContinueButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        pauseContinueButton.isEnabled = true
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
            urlLaberl.bottomAnchor.constraint(lessThanOrEqualTo: progressView.topAnchor, constant: -8),
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            pauseContinueButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            pauseContinueButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            pauseContinueButton.heightAnchor.constraint(equalToConstant: 48),
            pauseContinueButton.widthAnchor.constraint(equalToConstant: 48),
            pauseContinueButton.bottomAnchor.constraint(lessThanOrEqualTo: progressView.topAnchor, constant: -8),
            infoLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            infoLabel.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 4),
            infoLabel.trailingAnchor.constraint(equalTo: pauseContinueButton.leadingAnchor, constant: -4),
            infoLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    @objc
    func pauseContinueButtonDidTap() {
        pauseContinueAction?()
        pauseContinueButton.isEnabled = false
    }
}

//
//  SettingsViewController.swift
//  SibersTestTask
//
//  Created by Vladislav Mishukov on 17.07.2026.
//

import UIKit

final class SettingsViewController: UIViewController {
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let maxSegmentsLabel = SettingsViewController.makeLabel(text: "Max segments per file")
    private let maxSegmentsTextField = SettingsViewController.makeTextField(placeholder: "1–100", keyboardType: .numberPad)
    
    private let maxSegmentSizeLabel = SettingsViewController.makeLabel(text: "Max segment size (MB)")
    private let maxSegmentSizeTextField = SettingsViewController.makeTextField(placeholder: "1–1024", keyboardType: .numberPad)
    
    private let maxConcurrentFilesLabel = SettingsViewController.makeLabel(text: "Concurrent files")
    private let maxConcurrentFilesTextField = SettingsViewController.makeTextField(placeholder: "1–10", keyboardType: .numberPad)
    
    private let retryAttemptsLabel = SettingsViewController.makeLabel(text: "Retry attempts")
    private let retryAttemptsTextField = SettingsViewController.makeTextField(placeholder: "0–10", keyboardType: .numberPad)
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupUI()
        setupConstraints()
        loadCurrentSettings()
        setupTextFieldActions()
        hideKeyboardWhenTappedAround()
    }
}

// MARK: - PRIVATE METHODS
private extension SettingsViewController {
    
    func setupUI() {
        stackView.addArrangedSubview(makeFieldBlock(label: maxSegmentsLabel, textField: maxSegmentsTextField))
        stackView.addArrangedSubview(makeFieldBlock(label: maxSegmentSizeLabel, textField: maxSegmentSizeTextField))
        stackView.addArrangedSubview(makeFieldBlock(label: maxConcurrentFilesLabel, textField: maxConcurrentFilesTextField))
        stackView.addArrangedSubview(makeFieldBlock(label: retryAttemptsLabel, textField: retryAttemptsTextField))
        
        contentView.addSubview(stackView)
        scrollView.addSubview(contentView)
        view.addSubview(scrollView)
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    func setupNavigationBar() {
        navigationItem.title = "Download Settings"
    }
    
    func loadCurrentSettings() {
        let defaults = UserDefaults.standard
        maxSegmentsTextField.text = "\(defaults.integer(forKey:  DefaultsKeys.maxSegmentsPerFile.rawValue))"
        maxSegmentSizeTextField.text = "\(defaults.integer(forKey: DefaultsKeys.maxSegmentSizeMB.rawValue))"
        maxConcurrentFilesTextField.text = "\(defaults.integer(forKey: DefaultsKeys.maxConcurrentFiles.rawValue))"
        retryAttemptsTextField.text = "\(defaults.integer(forKey: DefaultsKeys.retryAttempts.rawValue))"
    }
    
    // MARK: - Immediate save on editing change
    func setupTextFieldActions() {
        maxSegmentsTextField.addTarget(self, action: #selector(maxSegmentsChanged), for: .editingChanged)
        maxSegmentSizeTextField.addTarget(self, action: #selector(maxSegmentSizeChanged), for: .editingChanged)
        maxConcurrentFilesTextField.addTarget(self, action: #selector(maxConcurrentFilesChanged), for: .editingChanged)
        retryAttemptsTextField.addTarget(self, action: #selector(retryAttemptsChanged), for: .editingChanged)
    }
    
    @objc func maxSegmentsChanged() {
        if let value = Int(maxSegmentsTextField.text ?? ""), (1...100).contains(value) {
            UserDefaults.standard.set(value, forKey: "maxSegmentsPerFile")
        }
    }
    
    @objc func maxSegmentSizeChanged() {
        if let value = Int(maxSegmentSizeTextField.text ?? ""), (1...1024).contains(value) {
            UserDefaults.standard.set(value, forKey: "maxSegmentSizeMB")
        }
    }
    
    @objc func maxConcurrentFilesChanged() {
        if let value = Int(maxConcurrentFilesTextField.text ?? ""), (1...10).contains(value) {
            UserDefaults.standard.set(value, forKey: "maxConcurrentFiles")
        }
    }
    
    @objc func retryAttemptsChanged() {
        if let value = Int(retryAttemptsTextField.text ?? ""), (0...10).contains(value) {
            UserDefaults.standard.set(value, forKey: "retryAttempts")
        }
    }
    
    // MARK: - Helpers
    func makeFieldBlock(label: UILabel, textField: UITextField) -> UIStackView {
        let verticalStack = UIStackView(arrangedSubviews: [label, textField])
        verticalStack.axis = .vertical
        verticalStack.spacing = 4
        return verticalStack
    }
    
    func hideKeyboardWhenTappedAround() {
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }
    
    // MARK: - Factory
    static func makeLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .medium)
        return label
    }
    
    static func makeTextField(placeholder: String, keyboardType: UIKeyboardType) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        field.borderStyle = .roundedRect
        return field
    }
}

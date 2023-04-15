//
//  ViewController.swift
//  LivePhotos
//
//  Created by yangjie.layer on 2023/3/29.
//

import UIKit
import AVKit
import Combine
import PhotosUI

enum LivePhotosPageStyle: Int {
    case disassemble // Live Photos disassemble
    case assemble // Live Photos assemble
}

class LivePhotosViewController: UIViewController {
    
    // MARK: - Properties
    
    var subscriptions = Set<AnyCancellable>()
    
    /// Current scene type
    let style = CurrentValueSubject<LivePhotosPageStyle, Never>(.disassemble)
    
    /// Current photo url
    let photoURL = CurrentValueSubject<URL?, Never>(nil)
    
    /// Current video url
    let videoURL = CurrentValueSubject<URL?, Never>(nil)
    
    /// Asemble URL
    let asembleURLs = CurrentValueSubject<(URL?, URL?)?, Never>(nil)
    
    // MARK: - UI Properties
    
    /// NavagationItem's segmentedControl, switch between disassemble and assemble
    private lazy var segmentedControl = {
        let segmentedControl = UISegmentedControl(items: ["Disassemble", "Assemble"])
        segmentedControl.backgroundColor = .gray.withAlphaComponent(0.1)
        segmentedControl.addAction(UIAction(handler: { [weak self] _ in
            guard let self else { return }
            self.segmentValueDidChange(segmentedControl)
        }), for: .valueChanged)
        return segmentedControl
    }()
    
    /// NavagationItem's icon, shows whether it is currently disassemble or assemble
    private var iconImageView = UIImageView()
    
    /// The main Button at the bottom, for Live Photo selection or synthesis
    private lazy var mainButton = {
        var config = UIButton.Configuration.filled()
        config.buttonSize = .large
        config.cornerStyle = .large
        config.image = UIImage(systemName: "photo.on.rectangle.angled")
        config.imagePadding = 10.0
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .boldSystemFont(ofSize: 15.0)
            return outgoing
        }
        let button = UIButton(configuration: config)
        button.configurationUpdateHandler = { button in
            let title: String
            let color: UIColor
            switch(self.style.value) {
            case .disassemble:
                title = "Pick A Live Photo"
                color = .systemBlue
            case .assemble:
                title = "Save the Live Photo"
                color = .systemPink
            }
            button.configuration?.title = title
            button.configuration?.baseBackgroundColor = color
        }
        button.addAction(UIAction(handler: { [weak self] _ in
            guard let self else { return }
            switch(self.style.value) {
            case .disassemble:
                self.pickButtonDidSelect(button)
            case .assemble:
                self.saveButtonDidSelect(button)
            }
        }), for: .touchUpInside)
        return button
    }()
    
    /// Live Photo Display Container
    let livePhotoView = {
        let livePhotoView = PHLivePhotoView()
        livePhotoView.backgroundColor = .gray.withAlphaComponent(0.1)
        livePhotoView.contentMode = .scaleAspectFit
        livePhotoView.layer.cornerRadius = 8.0
        return livePhotoView
    }()
    
    /// Icon on the Live Photo showcase container
    private var livePhotoIcon = UIImageView()
    
    /// Photo display container
    let leftImageView = {
        let imageView = UIImageView()
        imageView.backgroundColor = .gray.withAlphaComponent(0.1)
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 8.0
        return imageView
    }()
    
    /// Video display container
    private let rightPlayerViewController = {
        let playerViewController = AVPlayerViewController()
        playerViewController.view.backgroundColor = .gray.withAlphaComponent(0.1)
        playerViewController.view.layer.cornerRadius = 8.0
        return playerViewController
    }()
    
    /// Left photo button
    private lazy var leftButton = {
        var config = UIButton.Configuration.filled()
        config.buttonSize = .large
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .boldSystemFont(ofSize: 15.0)
            return outgoing
        }
        let button = UIButton(configuration: config)
        button.configurationUpdateHandler = { button in
            let title: String
            let color: UIColor
            switch(self.style.value) {
            case .disassemble:
                title = "Save Photo"
                color = .systemBlue
            case .assemble:
                title = "Pick Photo"
                color = .systemPink
            }
            button.configuration?.title = title
            button.configuration?.baseBackgroundColor = color
        }
        button.addAction(UIAction(handler: { [weak self] _ in
            guard let self else { return }
            switch(self.style.value) {
            case .disassemble:
                self.savePhotoButtonDidSelect(button)
            case .assemble:
                self.pickPhotoButtonDidSelect(button)
            }
        }), for: .touchUpInside)
        return button
    }()
    
    /// Right video button
    private lazy var rightButton = {
        var config = UIButton.Configuration.filled()
        config.buttonSize = .large
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .boldSystemFont(ofSize: 15.0)
            return outgoing
        }
        let button = UIButton(configuration: config)
        button.configurationUpdateHandler = { button in
            let title: String
            let color: UIColor
            switch(self.style.value) {
            case .disassemble:
                title = "Save Video"
                color = .systemBlue
            case .assemble:
                title = "Pick Video"
                color = .systemPink
            }
            button.configuration?.title = title
            button.configuration?.baseBackgroundColor = color
        }
        button.addAction(UIAction(handler: { [weak self] _ in
            guard let self else { return }
            switch(self.style.value) {
            case .disassemble:
                self.saveVideoButtonDidSelect(button)
            case .assemble:
                self.pickVideoButtonDidSelect(button)
            }
        }), for: .touchUpInside)
        return button
    }()
    
    let progressView: UIProgressView = UIProgressView()
    
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSubscibers()
        setUPAuthorization()
    }
    
    /// Adapt to light and dark mode switching
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateLivePhotoIcon()
    }
}

// MARK: - Set up and update the UI

extension LivePhotosViewController {
    
    private func setupUI() {
        let stackView = UIStackView(arrangedSubviews: [segmentedControl, iconImageView])
        stackView.spacing = 10.0
        navigationItem.titleView = stackView
        view.addSubview(mainButton)
        mainButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainButton.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20.0),
            mainButton.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20.0),
            mainButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -40.0),
            mainButton.heightAnchor.constraint(equalToConstant: 40.0)
        ])
        view.addSubview(livePhotoView)
        livePhotoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            livePhotoView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20.0),
            livePhotoView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20.0),
            livePhotoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10.0),
            livePhotoView.heightAnchor.constraint(equalToConstant: 220.0)
        ])
        view.addSubview(livePhotoIcon)
        livePhotoIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            livePhotoIcon.leftAnchor.constraint(equalTo: livePhotoView.leftAnchor, constant: 10.0),
            livePhotoIcon.topAnchor.constraint(equalTo: livePhotoView.topAnchor, constant: 10.0),
            livePhotoIcon.widthAnchor.constraint(equalToConstant: 30.0),
            livePhotoIcon.heightAnchor.constraint(equalToConstant: 30.0)
        ])
        view.addSubview(leftImageView)
        leftImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftImageView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20.0),
            leftImageView.rightAnchor.constraint(equalTo: view.centerXAnchor, constant: -10.0),
            leftImageView.topAnchor.constraint(equalTo: livePhotoView.bottomAnchor, constant: 20.0),
            leftImageView.heightAnchor.constraint(equalToConstant: 220.0)
        ])
        view.addSubview(rightPlayerViewController.view)
        rightPlayerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rightPlayerViewController.view.leftAnchor.constraint(equalTo: view.centerXAnchor, constant: 10.0),
            rightPlayerViewController.view.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20.0),
            rightPlayerViewController.view.topAnchor.constraint(equalTo: livePhotoView.bottomAnchor, constant: 20.0),
            rightPlayerViewController.view.heightAnchor.constraint(equalToConstant: 220.0)
        ])
        view.addSubview(leftButton)
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftButton.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20.0),
            leftButton.rightAnchor.constraint(equalTo: view.centerXAnchor, constant: -10.0),
            leftButton.topAnchor.constraint(equalTo: leftImageView.bottomAnchor, constant: 20.0),
            leftButton.heightAnchor.constraint(equalToConstant: 40.0)
        ])
        view.addSubview(rightButton)
        rightButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rightButton.leftAnchor.constraint(equalTo: view.centerXAnchor, constant: 10.0),
            rightButton.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20.0),
            rightButton.topAnchor.constraint(equalTo: rightPlayerViewController.view.bottomAnchor, constant: 20.0),
            rightButton.heightAnchor.constraint(equalToConstant: 40.0)
        ])
        
        view.addSubview(progressView)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressView.leftAnchor.constraint(equalTo: mainButton.leftAnchor),
            progressView.rightAnchor.constraint(equalTo: mainButton.rightAnchor),
            progressView.bottomAnchor.constraint(equalTo: mainButton.topAnchor, constant: -20.0),
            progressView.heightAnchor.constraint(equalToConstant: 10.0)
        ])
        
        updateLivePhotoIcon()
    }
    
    private func updateLivePhotoIcon() {
        let mode = UITraitCollection.current.userInterfaceStyle;
        switch mode {
        case .dark:
            livePhotoIcon.image = UIImage(systemName: "livephoto")?.withTintColor(.label, renderingMode: .alwaysOriginal)
        case .light, .unspecified:
            livePhotoIcon.image = UIImage(systemName: "livephoto")?.withTintColor(.label, renderingMode: .alwaysOriginal)
        @unknown default:
            fatalError()
        }
    }
    
    private func setupSubscibers() {
        style.sink { [weak self] style in
            guard let self else { return }
            self.segmentedControl.selectedSegmentIndex = style.rawValue
        }.store(in: &subscriptions)
        
        style.sink { [weak self] style in
            guard let self else { return }
            let image: UIImage?
            let config = UIImage.SymbolConfiguration(weight: .bold)
            switch(style) {
            case .disassemble:
                image = UIImage(systemName: "rectangle.expand.vertical", withConfiguration: config)
            case .assemble:
                image = UIImage(systemName: "rectangle.compress.vertical", withConfiguration: config)
            }
            self.iconImageView.image = image?.withTintColor(.label, renderingMode: .alwaysOriginal)
        }.store(in: &subscriptions)
        
        style.sink { [weak self] style in
            guard let self else { return }
            self.mainButton.setNeedsUpdateConfiguration()
            self.leftButton.setNeedsUpdateConfiguration()
            self.rightButton.setNeedsUpdateConfiguration()
        }.store(in: &subscriptions)
        
        style.sink { [weak self] style in
            guard let self else { return }
            let color: UIColor
            switch(style) {
            case .disassemble:
                color = .systemBlue
            case .assemble:
                color = .systemPink
            }
            self.progressView.progressTintColor = color
        }.store(in: &subscriptions)
        
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime).sink { [weak self] _ in
            if let player = self?.rightPlayerViewController.player {
                player.seek(to: CMTimeMake(value: 0, timescale: 600))
                player.play()
            }
        }.store(in: &subscriptions)
        
        setupAsembleSubscibers()
    }
}

// MARK: - Actions

extension LivePhotosViewController {
    
    private func setUPAuthorization() {
        Task {
            await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
    }
    
    private func segmentValueDidChange(_ sender: UISegmentedControl) {
        progressView.progress = 0
        livePhotoView.livePhoto = nil
        leftImageView.image = nil
        rightPlayerViewController.player = nil
        photoURL.send(nil)
        videoURL.send(nil)
        asembleURLs.send(nil)
        style.send(LivePhotosPageStyle(rawValue: sender.selectedSegmentIndex)!)
    }
    
    func playVideo(_ url:URL) {
        Task {
            let asset = AVAsset(url:url)
            if try await asset.load(.isPlayable) {
                let playerItem = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: playerItem)
                rightPlayerViewController.player = player
                player.play()
            }
        }
    }
}

// MARK: - PHPickerViewControllerDelegate

extension LivePhotosViewController: PHPickerViewControllerDelegate {
    
    /// Present `PHPickerViewController`
    func pick(_ filter: PHPickerFilter) {
        var config = PHPickerConfiguration()
        config.filter = filter
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        defer { picker.dismiss(animated: true) }
        switch(style.value) {
        case .disassemble:
            disassemblePicker(picker, didFinishPicking: results)
        case .assemble:
            assemblePicker(picker, didFinishPicking: results)
        }
    }
}

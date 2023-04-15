//
//  LivePhotosViewController+Asemble.swift
//  LivePhotos
//
//  Created by yangjie.layer on 2023/4/1.
//

import UIKit
import PhotosUI

// MARK: - Asemble Action

extension LivePhotosViewController {
    
    func saveButtonDidSelect(_ sender: UIButton) {
        guard let (photoURL, videURL) = asembleURLs.value,
              let photoURL, let videURL else {
            return
        }
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            creationRequest.addResource(with: PHAssetResourceType.photo, fileURL: photoURL, options: options)
            creationRequest.addResource(with: PHAssetResourceType.pairedVideo, fileURL: videURL, options: options)
        }, completionHandler: { success, _ in
            Toast.show(success ? "Saved successfully" : "An error occurred")
        })
    }
    
    func pickPhotoButtonDidSelect(_ sender: UIButton) {
        pick(.any(of: [.images]))
    }
    
    func pickVideoButtonDidSelect(_ sender: UIButton) {
        pick(.any(of: [.videos]))
    }
    
    func assemblePicker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let itemProvider = results.first?.itemProvider else {
            return
        }
        if itemProvider.canLoadObject(ofClass: UIImage.self) {
            itemProvider.loadObject(ofClass: UIImage.self) { [weak self] photo, error in
                guard let self, let photo = photo as? UIImage else {
                    return
                }
                Task { @MainActor in
                    self.leftImageView.image = photo
                }
                do {
                    let cachesDirectory = try self.cachesDirectory()
                    let targetURL = cachesDirectory.appendingPathComponent(NSUUID().uuidString).appendingPathExtension("jpg")
                    try photo.pngData()?.write(to: targetURL)
                    self.photoURL.send(targetURL)
                } catch {
                    Toast.show("An error occurred")
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            itemProvider.loadFileRepresentation(forTypeIdentifier: itemProvider.registeredTypeIdentifiers.first!) { [weak self] url, error in
                guard let self, let url = url else {
                    return
                }
                do {
                    let cachesDirectory = try self.cachesDirectory()
                    let targetURL = cachesDirectory.appendingPathComponent(NSUUID().uuidString).appendingPathExtension(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: targetURL)
                    self.videoURL.send(targetURL)
                    self.playVideo(targetURL)
                } catch {
                    Toast.show("An error occurred")
                }
            }
        }
    }
    
    private func cachesDirectory() throws -> URL {
        let cachesDirectoryURL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let cachesDirectory = cachesDirectoryURL.appendingPathComponent("asemble", isDirectory: true)
        if !FileManager.default.fileExists(atPath: cachesDirectory.absoluteString) {
            try FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        return cachesDirectory
    }
}

extension LivePhotosViewController {
    
    func setupAsembleSubscibers() {
        photoURL
            .combineLatest(videoURL)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] photoURL, videoURL in
                guard let self,
                          self.style.value == .assemble,
                let photoURL = photoURL,
                let videoURL = videoURL else {
                    return
                }
                self.assemble(photo: photoURL, video: videoURL)
            }.store(in: &subscriptions)
    }
    
    func assemble(photo: URL, video: URL) {
        progressView.progress = 0
        Task {
            let (livePhoto, (photoURL, videoURL)) = try await LivePhotos.sharedInstance.assemble(photoURL:photo, videoURL:video) { [weak self] process in
                guard let self else { return }
                self.progressView.progress = process
            }
            Task { @MainActor in
                self.livePhotoView.livePhoto = livePhoto
            }
            asembleURLs.send((photoURL, videoURL))
        }
    }
    
}

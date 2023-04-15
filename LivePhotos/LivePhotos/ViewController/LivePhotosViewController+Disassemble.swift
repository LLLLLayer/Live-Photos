//
//  LivePhotosViewController+Disassemble.swift
//  LivePhotos
//
//  Created by yangjie.layer on 2023/4/1.
//

import AVKit
import Combine
import PhotosUI

extension LivePhotosViewController {
    
    /// Select the LivePhoto photo in the photo app
    func pickButtonDidSelect(_ sender: UIButton) {
        pick(.any(of: [.livePhotos]))
    }
    
    /// Save the photo
    func savePhotoButtonDidSelect(_ sender: UIButton) {
        guard let photoURL = self.photoURL.value,
              !FileManager.default.fileExists(atPath: photoURL.absoluteString) else {
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: photoURL)
        }, completionHandler: { success, error in
            Toast.show("\(success ? "Saved successfully" : "Save failed")")
        })
    }
    
    /// Save the video
    func saveVideoButtonDidSelect(_ sender: UIButton) {
        guard let videoURL = self.videoURL.value,
              !FileManager.default.fileExists(atPath: videoURL.absoluteString) else {
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }, completionHandler: { success, error in
            Toast.show("\(success ? "Saved successfully" : "Save failed")")
        })
    }
    
    func disassemblePicker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let itemProvider = results.first?.itemProvider,
              itemProvider.canLoadObject(ofClass: PHLivePhoto.self) else {
            Toast.show("Pick failed")
            return
        }
        itemProvider.loadObject(ofClass: PHLivePhoto.self) { [weak self] livePhoto, _ in
            Task { @MainActor in
                guard let self, let livePhoto = livePhoto as? PHLivePhoto else {
                    Toast.show("Load failed")
                    return
                }
                self.livePhotoView.livePhoto = livePhoto
                self.disassemble(livePhoto: livePhoto)
            }
        }
    }
}

extension LivePhotosViewController {
    
    func disassemble(livePhoto: PHLivePhoto) {
        self.progressView.progress = 0
        Task {
            do {
                // Disassemble the livePhoto
                let (photoURL, videoURL) = try await LivePhotos.sharedInstance.disassemble(livePhoto: livePhoto)
                await MainActor.run {  self.progressView.progress = 1 }
                self.photoURL.send(photoURL)
                self.videoURL.send(videoURL)
                // Show the photo
                if FileManager.default.fileExists(atPath: photoURL.path) {
                    guard let photo = UIImage(contentsOfFile: photoURL.path) else { return }
                    await MainActor.run { leftImageView.image = photo }
                }
                // show the video
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    playVideo(URL(fileURLWithPath: videoURL.path))
                }
            } catch {
                await MainActor.run { Toast.show("Disassemble failed") }
            }
        }
    }
}

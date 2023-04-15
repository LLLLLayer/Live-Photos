//
//  LivePhotos.swift
//  LivePhotos
//
//  Created by yangjie.layer on 2023/3/31.
//

import UIKit
import Photos
import AVFoundation
import MobileCoreServices

enum LivePhotosError: Error {
    case noCachesDirectory
}

enum LivePhotosDisassembleError: Error {
    case requestDataFailed
    case noFilenameExtension
}

enum LivePhotosAssembleError: Error {
    case addPhotoIdentifierFailed
    case createDestinationImageFailed
    case writingVideoFailed
    case writingAudioFailed
    case requestFailed
    case loadTracksFailed
}

actor LivePhotos {
    static let sharedInstance = LivePhotos()
}

// MARK: - disassemble

extension LivePhotos {
    
    func disassemble(livePhoto: PHLivePhoto) async throws -> (URL, URL) {
        let assetResources = PHAssetResource.assetResources(for: livePhoto)
        let list = try await withThrowingTaskGroup(of: (PHAssetResource, Data).self) { taskGroup in
            for assetResource in assetResources {
                taskGroup.addTask {
                    return try await withCheckedThrowingContinuation { continuation in
                        let dataBuffer = NSMutableData()
                        let options = PHAssetResourceRequestOptions()
                        options.isNetworkAccessAllowed = true
                        PHAssetResourceManager.default().requestData(for: assetResource, options: options) { data in
                            dataBuffer.append(data)
                        } completionHandler: { error in
                            guard error == nil else {
                                continuation.resume(throwing: LivePhotosDisassembleError.requestDataFailed)
                                return
                            }
                            continuation.resume(returning: (assetResource, dataBuffer as Data))
                        }
                    }
                }
            }
            var results: [(PHAssetResource, Data)] = []
            for try await result in taskGroup {
                results.append(result)
            }
            return results
        }
        guard let photo = (list.first { $0.0.type == .photo }),
              let video = (list.first { $0.0.type == .pairedVideo }) else {
            throw LivePhotosDisassembleError.requestDataFailed
        }
        let cachesDirectory = try cachesDirectory()
        let photoURL = try save(photo.0, data: photo.1, to: cachesDirectory)
        let videoURL = try save(video.0, data: video.1, to: cachesDirectory)
        return (photoURL, videoURL)
    }
    
    private func save(_ assetResource: PHAssetResource, data: Data, to url: URL) throws -> URL {
        guard let ext = UTType(assetResource.uniformTypeIdentifier)?.preferredFilenameExtension else {
            throw LivePhotosDisassembleError.noFilenameExtension
        }
        let destinationURL = url.appendingPathComponent(NSUUID().uuidString).appendingPathExtension(ext as String)
        try data.write(to: destinationURL, options: [Data.WritingOptions.atomic])
        return destinationURL
    }
}

// MARK: - Assemble

extension LivePhotos {
    
    func assemble(photoURL: URL, videoURL: URL, progress: ((Float) -> Void)? = nil) async throws -> (PHLivePhoto, (URL, URL)) {
        let cacheDirectory = try cachesDirectory()
        let identifier = UUID().uuidString
        let pairedPhotoURL = try addIdentifier(
            identifier,
            fromPhotoURL: photoURL,
            to: cacheDirectory.appendingPathComponent(identifier).appendingPathExtension("jpg"))
        let pairedVideoURL = try await addIdentifier(
            identifier,
            fromVideoURL: videoURL,
            to: cacheDirectory.appendingPathComponent(identifier).appendingPathExtension("mov"),
            progress: progress)
        
        let livePhoto = try await withCheckedThrowingContinuation({ continuation in
            PHLivePhoto.request(
                withResourceFileURLs: [pairedPhotoURL, pairedVideoURL],
                placeholderImage: nil,
                targetSize: .zero,
                contentMode: .aspectFill) { livePhoto, info in
                    if let isDegraded = info[PHLivePhotoInfoIsDegradedKey] as? Bool, isDegraded {
                        return
                    }
                    if let livePhoto {
                        continuation.resume(returning: livePhoto)
                    } else {
                        continuation.resume(throwing: LivePhotosAssembleError.requestFailed)
                    }
                }
        })
        return (livePhoto, (pairedPhotoURL, pairedVideoURL))
    }
    
private func addIdentifier(_ identifier: String, fromPhotoURL photoURL: URL, to destinationURL: URL) throws -> URL {
    guard let imageSource = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
          let imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
          var imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable : Any] else {
        throw LivePhotosAssembleError.addPhotoIdentifierFailed
    }
    let identifierInfo = ["17" : identifier]
    imageProperties[kCGImagePropertyMakerAppleDictionary] = identifierInfo
    guard let imageDestination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw LivePhotosAssembleError.createDestinationImageFailed
    }
    CGImageDestinationAddImage(imageDestination, imageRef, imageProperties as CFDictionary)
    if CGImageDestinationFinalize(imageDestination) {
        return destinationURL
    } else {
        throw LivePhotosAssembleError.createDestinationImageFailed
    }
}

private func addIdentifier(
    _ identifier: String,
    fromVideoURL videoURL: URL,
    to destinationURL: URL,
    progress: ((Float) -> Void)? = nil
) async throws -> URL {
    
    let asset = AVURLAsset(url: videoURL)
    // --- Reader ---
    
    // Create the video reader
    let videoReader = try AVAssetReader(asset: asset)
    
    // Create the video reader output
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw LivePhotosAssembleError.loadTracksFailed }
    let videoReaderOutputSettings : [String : Any] = [kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA]
    let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderOutputSettings)
    
    // Add the video reader output to video reader
    videoReader.add(videoReaderOutput)
    
    // Create the audio reader
    let audioReader = try AVAssetReader(asset: asset)
    
    // Create the audio reader output
    guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else { throw LivePhotosAssembleError.loadTracksFailed }
    let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
    
    // Add the audio reader output to audioReader
    audioReader.add(audioReaderOutput)
    
    // --- Writer ---
    
    // Create the asset writer
    let assetWriter = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
    
    // Create the video writer input
    let videoWriterInputOutputSettings : [String : Any] = [
        AVVideoCodecKey : AVVideoCodecType.h264,
        AVVideoWidthKey : try await videoTrack.load(.naturalSize).width,
        AVVideoHeightKey : try await videoTrack.load(.naturalSize).height]
    let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterInputOutputSettings)
    videoWriterInput.transform = try await videoTrack.load(.preferredTransform)
    videoWriterInput.expectsMediaDataInRealTime = true
    
    // Add the video writer input to asset writer
    assetWriter.add(videoWriterInput)
    
    // Create the audio writer input
    let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
    audioWriterInput.expectsMediaDataInRealTime = false
    
    // Add the audio writer input to asset writer
    assetWriter.add(audioWriterInput)
    
    // Create the identifier metadata
    let identifierMetadata = metadataItem(for: identifier)
    // Create still image time metadata track
    let stillImageTimeMetadataAdaptor = stillImageTimeMetadataAdaptor()
    assetWriter.metadata = [identifierMetadata]
    assetWriter.add(stillImageTimeMetadataAdaptor.assetWriterInput)
    
    // Start the asset writer
    assetWriter.startWriting()
    assetWriter.startSession(atSourceTime: .zero)
    
    // Add still image metadata
    let frameCount = try await asset.frameCount()
    let stillImagePercent: Float = 0.5
    await stillImageTimeMetadataAdaptor.append(
        AVTimedMetadataGroup(
            items: [stillImageTimeMetadataItem()],
            timeRange: try asset.makeStillImageTimeRange(percent: stillImagePercent, inFrameCount: frameCount)))
    
    async let writingVideoFinished: Bool = withCheckedThrowingContinuation { continuation in
        Task {
            videoReader.startReading()
            var currentFrameCount = 0
            videoWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "videoWriterInputQueue")) {
                while videoWriterInput.isReadyForMoreMediaData {
                    if let sampleBuffer = videoReaderOutput.copyNextSampleBuffer()  {
                        currentFrameCount += 1
                        if let progress {
                            let progressValue = min(Float(currentFrameCount)/Float(frameCount), 1.0)
                            Task { @MainActor in
                                progress(progressValue)
                            }
                        }
                        if !videoWriterInput.append(sampleBuffer) {
                            videoReader.cancelReading()
                            continuation.resume(throwing: LivePhotosAssembleError.writingVideoFailed)
                            return
                        }
                    } else {
                        videoWriterInput.markAsFinished()
                        continuation.resume(returning: true)
                        return
                    }
                }
            }
        }
    }
    
    async let writingAudioFinished: Bool = withCheckedThrowingContinuation { continuation in
        Task {
            audioReader.startReading()
            audioWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audioWriterInputQueue")) {
                while audioWriterInput.isReadyForMoreMediaData {
                    if let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() {
                        if !audioWriterInput.append(sampleBuffer) {
                            audioReader.cancelReading()
                            continuation.resume(throwing: LivePhotosAssembleError.writingAudioFailed)
                            return
                        }
                    } else {
                        audioWriterInput.markAsFinished()
                        continuation.resume(returning: true)
                        return
                    }
                }
            }
        }
    }
    
    await (_, _) = try (writingVideoFinished, writingAudioFinished)
    await assetWriter.finishWriting()
    return destinationURL
}
    
    private func metadataItem(for identifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata // "mdta"
        item.dataType = "com.apple.metadata.datatype.UTF-8"
        item.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as any NSCopying & NSObjectProtocol // "com.apple.quicktime.content.identifier"
        item.value = identifier as any NSCopying & NSObjectProtocol
        return item
    }
    
    private func stillImageTimeMetadataAdaptor() -> AVAssetWriterInputMetadataAdaptor {
        let quickTimeMetadataKeySpace = AVMetadataKeySpace.quickTimeMetadata.rawValue // "mdta"
        let stillImageTimeKey = "com.apple.quicktime.still-image-time"
        let spec: [NSString : Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as NSString : "\(quickTimeMetadataKeySpace)/\(stillImageTimeKey)",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as NSString : kCMMetadataBaseDataType_SInt8]
        var desc : CMFormatDescription? = nil
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray,
            formatDescriptionOut: &desc)
        let input = AVAssetWriterInput(
            mediaType: .metadata,
            outputSettings: nil,
            sourceFormatHint: desc)
        return AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
    }
    
    private func stillImageTimeMetadataItem() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = "com.apple.quicktime.still-image-time" as any NSCopying & NSObjectProtocol
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata // "mdta"
        item.value = 0 as any NSCopying & NSObjectProtocol
        item.dataType = kCMMetadataBaseDataType_SInt8 as String // "com.apple.metadata.datatype.int8"
        return item
    }
}

extension LivePhotos {
    
    private func cachesDirectory() throws -> URL {
        if let cachesDirectoryURL = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            let cachesDirectory = cachesDirectoryURL.appendingPathComponent("livePhotos", isDirectory: true)
            if !FileManager.default.fileExists(atPath: cachesDirectory.absoluteString) {
                try? FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true, attributes: nil)
            }
            return cachesDirectory
        }
        throw LivePhotosError.noCachesDirectory
    }
}


//
//  AVAsset+Extension.swift
//  LivePhotos
//
//  Created by yangjie.layer on 2023/4/9.
//

import UIKit
import AVFoundation

extension AVAsset {
    func frameCount(exact: Bool = false) async throws -> Int {
        let videoReader = try AVAssetReader(asset: self)
        guard let videoTrack = try await self.loadTracks(withMediaType: .video).first else { return 0 }
        if !exact {
            async let duration = CMTimeGetSeconds(self.load(.duration))
            async let nominalFrameRate = Float64(videoTrack.load(.nominalFrameRate))
            return try await Int(duration * nominalFrameRate)
        }
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoReader.add(videoReaderOutput)
        videoReader.startReading()
        var frameCount = 0
        while let _ = videoReaderOutput.copyNextSampleBuffer() {
            frameCount += 1
        }
        videoReader.cancelReading()
        return frameCount
    }
    
    func makeStillImageTimeRange(percent: Float, inFrameCount: Int = 0) async throws -> CMTimeRange {
        var time = try await self.load(.duration)
        var frameCount = inFrameCount
        if frameCount == 0 {
            frameCount = try await self.frameCount(exact: true)
        }
        let duration = Int64(Float(time.value) / Float(frameCount))
        time.value = Int64(Float(time.value) * percent)
        return CMTimeRangeMake(start: time, duration: CMTimeMake(value: duration, timescale: time.timescale))
    }
}

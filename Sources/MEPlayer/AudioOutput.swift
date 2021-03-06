//
//  AudioOutput.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import AudioToolbox
import CoreAudio
import CoreMedia
import QuartzCore

final class AudioOutput: FrameOutput {
    private let semaphore = DispatchSemaphore(value: 1)
    private var currentRenderReadOffset = 0
    private var currentRender: AudioFrame? {
        didSet {
            if currentRender == nil {
                currentRenderReadOffset = 0
            }
        }
    }

    weak var renderSource: OutputRenderSourceDelegate?
    let audioPlayer: AudioPlayer = AudioGraphPlayer()

    init() {
        audioPlayer.delegate = self
    }

    func play() {
        audioPlayer.play()
    }

    func pause() {
        audioPlayer.pause()
    }

    func flush() {
        semaphore.wait()
        currentRender = nil
        semaphore.signal()
    }

    func shutdown() {
        semaphore.wait()
        currentRender = nil
        semaphore.signal()
    }
}

extension AudioOutput: AudioPlayerDelegate {
    func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer, numberOfSamples: UInt32, numberOfChannels _: UInt32) {
        semaphore.wait()
        defer {
            semaphore.signal()
        }
        var ioDataWriteOffset = 0
        var numberOfSamples = Int(numberOfSamples)
        while numberOfSamples > 0 {
            if currentRender == nil {
                currentRender = renderSource?.getOutputRender(type: .audio) as? AudioFrame
            }
            guard let currentRender = currentRender else {
                return
            }
            let residueLinesize = currentRender.numberOfSamples - currentRenderReadOffset
            guard residueLinesize > 0 else {
                self.currentRender = nil
                continue
            }
            let framesToCopy = min(numberOfSamples, residueLinesize)
            let bytesToCopy = framesToCopy * MemoryLayout<Float>.size
            let offset = currentRenderReadOffset * MemoryLayout<Float>.size
            for i in 0 ..< min(ioData.count, currentRender.dataWrap.numberOfChannels) {
                (ioData[i].mData! + ioDataWriteOffset).copyMemory(from: currentRender.dataWrap.data[i]! + offset, byteCount: bytesToCopy)
            }
            numberOfSamples -= framesToCopy
            ioDataWriteOffset += bytesToCopy
            currentRenderReadOffset += framesToCopy
        }
    }

    func audioPlayerWillRenderSample(sampleTimestamp _: AudioTimeStamp) {}

    func audioPlayerDidRenderSample(sampleTimestamp _: AudioTimeStamp) {
        if let currentRender = currentRender {
            let currentPreparePosition = currentRender.position + currentRender.duration * Int64(currentRenderReadOffset) / Int64(currentRender.numberOfSamples)
            renderSource?.setAudio(time: currentRender.timebase.cmtime(for: currentPreparePosition))
        }
    }
}

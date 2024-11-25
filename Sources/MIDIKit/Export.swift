//
//  Export.swift
//  MIDIKit
//
//  Created by Vaida on 11/25/24.
//

import Foundation
import AVFoundation
import FinderItem


extension MIDIContainer {
    
    /// Export as audio.
    ///
    /// - Parameters:
    ///   - destination: The destination uses `wav` format.
    public func export(to destination: FinderItem) async throws {
        
        let audioEngine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        audioEngine.attach(sampler)
        audioEngine.connect(sampler, to: audioEngine.mainMixerNode, format: nil)
        
        let soundBankURL = Bundle.module.url(forResource: "Nice-Steinway-Lite-v3.0", withExtension: "sf2")!
        try sampler.loadSoundBankInstrument(at: soundBankURL, program: 0, bankMSB: 0x79, bankLSB: 0x00)
        
        let sequencer = AVAudioSequencer(audioEngine: audioEngine)
        try sequencer.load(from: self.data(), options: .smf_ChannelsToTracks)
        
        let audioFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        
        let outputFile = try AVAudioFile(forWriting: destination.url, settings: audioFormat.settings)
        
        // Configure the engine for offline rendering
        try audioEngine.enableManualRenderingMode(.offline, format: audioFormat, maximumFrameCount: 4096)
        try audioEngine.start()
        
        sequencer.prepareToPlay()
        try sequencer.start()
        
        // Render to audio file
        while audioEngine.manualRenderingSampleTime < AVAudioFramePosition(sequencer.duration * audioFormat.sampleRate) {
            let buffer = AVAudioPCMBuffer(pcmFormat: audioEngine.manualRenderingFormat, frameCapacity: 4096)!
            let status = try audioEngine.renderOffline(4096, to: buffer)
            
            if status == .success {
                try outputFile.write(from: buffer)
            } else if status == .error {
                throw NSError(domain: "MIDIExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error during rendering."])
            }
        }
        
        sequencer.stop()
        audioEngine.stop()
    }
    
}


extension AVAudioSequencer {
    var duration: TimeInterval {
        tracks.compactMap { $0.lengthInSeconds }.max() ?? 0
    }
}

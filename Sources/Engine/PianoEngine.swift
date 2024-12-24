//
//  PianoEngine.swift
//  Piano Transcriptionist
//
//  Created by Vaida on 10/2/24.
//

import Foundation
import Combine
import Observation
import AVFoundation
import FinderItem
import Synchronization
import Essentials


/// The engine handling all playbacks.
///
/// To use such engine, you must call ``start()`` first. Otherwise playback is not supported.
///
/// The duration is now unchecked. You must call `stop` to handle manually.
public final class PianoEngine {
    
    private var engine: AVAudioEngine?
    
    private var sampler: AVAudioUnitSampler?
    
    /// Plays the node.
    ///
    /// This function dispatch the job to a music queue. Hence this function is cheap.
    public func play(note: UInt8, velocity: UInt8) {
        sampler?.startNote(note, withVelocity: velocity, onChannel: 0)
    }
    
    /// Stop a note created by ``play(note:velocity:)``.
    ///
    /// This function dispatch the job to a music queue. Hence this function is cheap.
    public func stop(note: UInt8) {
        sampler?.stopNote(note, onChannel: 0)
    }
    
    /// Starts the sustain.
    ///
    /// This function dispatch the job to a music queue. Hence this function is cheap.
    public func pushSustain() {
        sampler?.sendController(64, withValue: 127, onChannel: 0)
    }
    
    /// Stops the sustain.
    ///
    /// This function dispatch the job to a music queue. Hence this function is cheap.
    public func popSustain() {
        sampler?.sendController(64, withValue: 0, onChannel: 0)
    }
    
    /// Stops all notes and sustains.
    ///
    /// This function dispatch the job to a music queue. Hence this function is cheap.
    public func stopAll() {
        for note in 21...108 {
            self.stop(note: UInt8(note))
        }
        
        self.popSustain()
    }
    
    /// A lightweight init. You can safely call it inside any `View` initializer.
    public init() {
        
    }
    
    @available(*, unavailable, renamed: "start()")
    public func prepare() async throws {
        
    }
    
    /// Starts the engine.
    ///
    /// This method must be called before any other methods.
    public func start() async throws {
        if let engine {
            try engine.start()
        } else {
            self.engine = AVAudioEngine()
            self.sampler = AVAudioUnitSampler()
            
            engine!.attach(sampler!)
            engine!.connect(sampler!, to: engine!.mainMixerNode, format: nil)
            
            try engine!.start()
            
            sampler!.sendController(72, withValue: 127, onChannel: 0)
            sampler!.sendController(73, withValue: 127, onChannel: 0)
            sampler!.sendController(75, withValue: 127, onChannel: 0)
            
            let soundBankURL = Bundle.module.url(forResource: "Nice-Steinway-Lite-v3.0", withExtension: "sf2")!
            try sampler!.loadSoundBankInstrument(at: soundBankURL, program: 0, bankMSB: 0x79, bankLSB: 0x00)
        }
    }
    
    /// Stops the engine.
    ///
    /// This method stops the audio engine and the audio hardware, and releases any allocated resources for the ``start()`` method. When your app doesn’t need to play audio, consider pausing or stopping the engine to minimize power consumption.
    public func stop() {
        self.engine?.stop()
        if let sampler {
            self.engine?.detach(sampler)
        }
        self.engine = nil
        self.sampler = nil
    }
    
    /// Pauses the audio engine.
    ///
    /// This method stops the audio engine and the audio hardware, but doesn’t deallocate the resources for the ``start()`` method. When your app doesn’t need to play audio, consider pausing or stopping the engine to minimize power consumption.
    ///
    /// You resume the audio engine by invoking ``start()``.
    public func pause() {
        self.engine?.pause()
    }
    
    deinit {
        self.stop()
    }
    
}

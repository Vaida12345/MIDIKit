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
        if engine != nil {
            try self.resume()
        } else {
            let engine = AVAudioEngine()
            let sampler = AVAudioUnitSampler()
            
            // our “early reflections” unit
            let delay = AVAudioUnitDelay()
            // our “reverb tail” unit
            let reverb = AVAudioUnitReverb()
            
            self.engine = engine
            self.sampler = sampler
            
            engine.attach(delay)
            engine.attach(reverb)
            engine.attach(sampler)
            
            // 2) Dry path: sampler → mainMixer
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            
            // 3) Wet path:
            // sampler → delay → reverb → mainMixer
            engine.connect(sampler, to: delay, format: nil)
            engine.connect(delay, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)
            
            // 4) Start engine
            try engine.start()
            
            // 5) Hook up sampler
            sampler.sendController(72, withValue: 127, onChannel: 0)
            sampler.sendController(73, withValue: 127, onChannel: 0)
            sampler.sendController(75, withValue: 127, onChannel: 0)
            
            let soundBankURL = Bundle.module.url(forResource: "Nice-Steinway-Lite-v3.0", withExtension: "sf2")!
            try sampler.loadSoundBankInstrument(at: soundBankURL, program: 0, bankMSB: 0x79, bankLSB: 0x00)
            
            // ————————————————————————————————————————————————
            // Now tune our two simple effects to approximate your
            // ChromaVerb settings:
            //
            //   attack   12%   → delay.wetDryMix = 12
            //   distance 87%   → delay.delayTime  = 0.087  seconds
            //   density  68%   → delay.feedback   =  68   %
            //
            delay.wetDryMix   = 12
            delay.delayTime   = 0.087
            delay.feedback    = 68
            delay.lowPassCutoff = 18_000   // roll off highs a bit
            
            //   size     36%   → pick a small–medium room preset
            //   decay    0.83s → mediumRoom is about 0.8s
            //   wet      28%   → reverb.wetDryMix = 28
            //   dry     100%   → our dry path is full-gain already
            reverb.loadFactoryPreset(.mediumRoom)
            reverb.wetDryMix = 28
        }
    }
    
    /// Stops the engine.
    ///
    /// This method stops the audio engine and the audio hardware, and releases any allocated resources for the ``start()`` method. When your app doesn’t need to play audio, consider pausing or stopping the engine to minimize power consumption.
    ///
    /// To restart the engine, call ``start()``.
    public func stop() {
        self.engine?.stop()
        if let sampler {
            self.engine?.detach(sampler)
        }
        self.engine = nil
        self.sampler = nil
    }
    
    /// Resumes the engine.
    ///
    /// This is the counterpart for ``pause()``.
    public func resume() throws {
        try engine?.start()
    }
    
    /// Pauses the audio engine.
    ///
    /// This method stops the audio engine and the audio hardware, but doesn’t deallocate the resources for the ``start()`` method. When your app doesn’t need to play audio, consider pausing or stopping the engine to minimize power consumption.
    ///
    /// You resume the audio engine by invoking ``start()`` or ``resume()``.
    public func pause() {
        self.engine?.pause()
    }
    
    deinit {
        self.stop()
    }
    
}

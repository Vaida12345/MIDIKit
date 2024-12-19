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
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 10.0, *)
public final class PianoEngine {
    
    private var engine: AVAudioEngine?
    
    private var sampler: AVAudioUnitSampler?
    
    
    @MainActor
    public func play(note: UInt8, velocity: UInt8) async {
        sampler?.startNote(note, withVelocity: velocity, onChannel: 0)
    }
    
    /// Stop a note created by ``play(note:velocity:)``.
    @MainActor
    public func stop(note: UInt8) async {
        sampler?.stopNote(note, onChannel: 0)
    }
    
    @MainActor
    public func pushSustain() async {
        sampler?.sendController(64, withValue: 127, onChannel: 0)
    }
    
    @MainActor
    public func popSustain() async {
        sampler?.sendController(64, withValue: 0, onChannel: 0)
    }
    
    @MainActor
    public func stopAll() async {
        for note in 21...108 {
            await self.stop(note: UInt8(note))
        }
        
        await self.popSustain()
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
    ///
    /// - Parameters:
    ///   - durationTracked: The auto stop of notes by passing `duration` only works when `durationTracked`.
    public func start(durationTracked: Bool = true) async throws {
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
    
    deinit {
        self.engine?.stop()
        if let sampler {
            self.engine?.detach(sampler)
        }
    }
    
}

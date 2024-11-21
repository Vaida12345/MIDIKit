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


/// The engine handling all playbacks.
public final class PianoEngine {
    
    let engine = AVAudioEngine()
    
    let sampler = AVAudioUnitSampler()
    
    /// beats per second is bpm / 60
    let beatsPerSecond: Double = 2
    
    /// The jobs are always sorted by the end date.
    var currentJobs: Heap<Job> = Heap(.minHeap)
    
    private var publisher: AnyCancellable?
    
    private var isSustainOn: Bool = false
    
    
    /// - Parameters:
    ///   - duration: Duration in beats
    public func play(note: UInt8, duration: Double, velocity: UInt8) {
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
        currentJobs.append(Job(note: note, end: Date() + duration))
    }
    
    public func pushSustain() {
        sampler.sendController(64, withValue: 127, onChannel: 0)
    }
    
    public func popSustain() {
        sampler.sendController(64, withValue: 0, onChannel: 0)
    }
    
    public func stopAll() {
        let jobs = currentJobs
        currentJobs = Heap(.minHeap)
        
        for job in jobs {
            sampler.stopNote(job.note, onChannel: 0)
        }
        
        self.popSustain()
    }
    
    private func checkForCompletedJobs(date: Date) {
        guard let job = self.currentJobs.first else { return }
        if date >= job.end {
            sampler.stopNote(job.note, onChannel: 0)
            
            self.currentJobs.removeFirst()
            self.checkForCompletedJobs(date: date)
        }
    }
    
    public init() {
        
    }
    
    public func prepare() async throws {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        
        try engine.start()
        
        sampler.sendController(72, withValue: 127, onChannel: 0)
        sampler.sendController(73, withValue: 127, onChannel: 0)
        sampler.sendController(75, withValue: 127, onChannel: 0)
        
        self.publisher = Timer.publish(every: 0.1, on: .current, in: .common) // on low frequency.
            .autoconnect()
            .sink { [weak self] date in
                self?.checkForCompletedJobs(date: date)
            }
        
        
        let soundBankURL = Bundle.module.url(forResource: "Nice-Steinway-Lite-v3.0", withExtension: "sf2")!
        try sampler.loadSoundBankInstrument(at: soundBankURL, program: 0, bankMSB: 0x79, bankLSB: 0x00)
    }
    
    deinit {
        self.publisher?.cancel()
        self.engine.stop()
        self.engine.detach(sampler)
    }
    
    
    struct Job: Equatable, Comparable {
        
        let note: UInt8
        
        let end: Date
        
        static func < (lhs: PianoEngine.Job, rhs: PianoEngine.Job) -> Bool {
            lhs.end < rhs.end
        }
        
    }
    
}

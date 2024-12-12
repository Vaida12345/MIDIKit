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


/// The engine handling all playbacks.
///
/// To use such engine, you must call ``start()`` first. Otherwise playback is not supported.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 10.0, *)
public final class PianoEngine {
    
    private var engine: AVAudioEngine?
    
    private var sampler: AVAudioUnitSampler?
    
    /// beats per second is bpm / 60
    private let beatsPerSecond: Double = 2
    
    /// The jobs are always sorted by the end date.
    private let currentJobs = Mutex(Heap<Job>(.minHeap))
    
    private var publisher: AnyCancellable?
    
    private var isSustainOn: Bool = false
    
    
    /// - Parameters:
    ///   - duration: Duration in beats. If `nil`, you need to manually stop the key using ``stop(note:)``.
    public func play(note: UInt8, duration: Double?, velocity: UInt8) async {
        sampler?.startNote(note, withVelocity: velocity, onChannel: 0)
        
        if let duration {
            currentJobs.withLock { jobs in
                jobs.append(Job(note: note, end: Date() + duration))
            }
        }
    }
    
    /// Stop a note created by ``play(note:duration:velocity:)`` with `duration = nil`.
    ///
    /// You *must* balance the number of ``play(note:duration:velocity:)`` and ``stop(note:)``.
    public func stop(note: UInt8) async {
        sampler?.stopNote(note, onChannel: 0)
    }
    
    public func pushSustain() async {
        sampler?.sendController(64, withValue: 127, onChannel: 0)
    }
    
    public func popSustain() async {
        sampler?.sendController(64, withValue: 0, onChannel: 0)
    }
    
    public func stopAll() async {
        let jobs = currentJobs.withLock { $0 }
        currentJobs.withLock { jobs in
            jobs = Heap(.minHeap)
        }
        
        for job in jobs {
            sampler?.stopNote(job.note, onChannel: 0)
        }
        
        await self.popSustain()
    }
    
    private func checkForCompletedJobs(date: Date) {
        let note: UInt8? = self.currentJobs.withLock { jobs in
            guard let firstJob = jobs.first else { return nil }
            
            if date >= firstJob.end {
                jobs.removeFirst()
                
                return firstJob.note
            }
            return nil
        }
        
        guard let note else { return }
        
        sampler?.stopNote(note, onChannel: 0)
        self.checkForCompletedJobs(date: date)
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
        self.engine = AVAudioEngine()
        self.sampler = AVAudioUnitSampler()
        
        engine!.attach(sampler!)
        engine!.connect(sampler!, to: engine!.mainMixerNode, format: nil)
        
        try engine!.start()
        
        sampler!.sendController(72, withValue: 127, onChannel: 0)
        sampler!.sendController(73, withValue: 127, onChannel: 0)
        sampler!.sendController(75, withValue: 127, onChannel: 0)
        
        self.publisher = Timer.publish(every: 0.1, on: .main, in: .common) // on low frequency.
            .autoconnect()
            .sink { [weak self] date in
                self?.checkForCompletedJobs(date: date)
            }
        
        
        let soundBankURL = Bundle.module.url(forResource: "Nice-Steinway-Lite-v3.0", withExtension: "sf2")!
        try sampler!.loadSoundBankInstrument(at: soundBankURL, program: 0, bankMSB: 0x79, bankLSB: 0x00)
    }
    
    deinit {
        self.publisher?.cancel()
        self.engine?.stop()
        if let sampler {
            self.engine?.detach(sampler)
        }
    }
    
    
    private struct Job: Equatable, Comparable {
        
        let note: UInt8
        
        let end: Date
        
        static func < (lhs: PianoEngine.Job, rhs: PianoEngine.Job) -> Bool {
            lhs.end < rhs.end
        }
        
    }
    
}

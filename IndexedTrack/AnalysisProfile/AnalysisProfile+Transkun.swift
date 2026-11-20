//
//  AnalysisProfile+Transkun.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


/// The profile for notes that [Transkun](https://github.com/Yujia-Yan/Transkun) transcribed.
///
/// Transkun's onsets sit on a grid of about 23 ms (1024 samples at 44.1 kHz), so the gap between two close notes comes in steps. Its offsets follow the release of the key, not the sustain pedal, so chord formation can use the release as a cue.
public struct TranskunProfile: AnalysisProfile {

    /// Creates the Transkun profile.
    public init() {

    }

    /// Groups the notes of `track` into chords with ``ChordArbiter/transkun``.
    public func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.transkun.formChords(in: track)
    }
    
    /// Finds the downbeats of `track` with ``DownbeatTracker/transkun``.
    public func downbeats(in track: IndexedTrack, prior: [Double]) -> [Double] {
        DownbeatTracker.transkun.downbeats(in: track, prior: prior)
    }

}


extension AnalysisProfile where Self == TranskunProfile {

    /// The profile for notes that [Transkun](https://github.com/Yujia-Yan/Transkun) transcribed.
    public static var transkun: TranskunProfile {
        TranskunProfile()
    }

}


extension ChordArbiter {

    /// The arbiter for notes that [Transkun](https://github.com/Yujia-Yan/Transkun) transcribed.
    ///
    /// Onsets sit on a grid of about 23 ms, so a gap of two frames is the only one that is a coin flip, and the offsets follow the keys, which makes the release a usable cue.
    ///
    /// Tuned on the transcription of the MAESTRO dataset.
    public static let transkun = ChordArbiter(
        stepLimit: 22.5,
        octaveLimit: 49.005,
        otherLimit: 39.69,
        previousWeight: 0.37,
        nextWeight: 0.14,
        isolationKnee: 2,
        isolationCap: 8,
        isolationFloor: 0.1,
        densityWeight: -0.18,
        densityCenter: 4,
        densityWindow: 150,
        releaseWeight: 0.1,
        releaseScale: 14.7,
        releaseCap: 3,
        velocityWeight: 0,
        velocityCenter: 64,
        velocityCap: 4,
        maximumSize: 24
    )

}


extension DownbeatTracker {
    
    /// [Transkun](https://github.com/Yujia-Yan/Transkun): its offsets follow the keys, so the duration cue weighs more.
    ///
    /// Tuned on the transkun transcriptions of the MAESTRO audio.
    public static let transkun = DownbeatTracker(
        bassWeight: 1.2,
        massWeight: 0.1,
        durationWeight: 1.5,
        chromaWeight: 0.6,
        wideChromaWeight: 1,
        pedalWeight: 0.7,
        gapWeight: 0.3,
        readsOffsets: true,
        tempoChangeCost: 30,
        beatFloor: 0.02,
        offBeatWeight: 0.6,
        downbeatGain: 1.6,
        downbeatCost: 0.7,
        meterChangeCost: 8,
        beatRegionDivisor: 20,
        tripleMeterBonus: 0.4,
        quadrupleMeterBonus: 0.6
    )
    
}

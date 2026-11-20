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

//
//  AnalysisProfile+Transkun.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


/// The profile for notes that [Transkun](https://github.com/Yujia-Yan/Transkun) transcribed.
///
/// Chords are formed with ``ChordArbiter/transkun`` and downbeats found with ``DownbeatTracker/transkun``, which both read the offsets, as Transkun's follow the keys. Artifacts are removed with ``GenericProfile/removingArtifacts(from:threshold:proximityThreshold:)``.
///
/// ## Shape of the Output
///
/// These figures were measured on the 1,276 performances of MAESTRO v3, transcribed by Transkun 1.3.0, against the MIDI that the piano recorded. A played note counts as found when the transcription has a note on its key whose onset is within 50 ms of it. Accuracy figures come from the 177 performances of the test split, as the model was trained on the others; the other figures come from all of them. The transcriptions were written by an earlier MIDIKit, whose rounding drifts by up to 10 ms over a long file; that drift was removed before measuring.
///
/// ### Timing
///
/// - Notes are decoded on frames of 1,024 samples at 44.1 kHz, 23.22 ms apart, frame k at (k + 0.47) × 23.22 ms into the recording, and each onset and offset is then moved from its frame by at most 0.44 frame, 10.3 ms.
/// - Onsets do not sit on a grid: they spread fairly evenly within 0.4 frame, 9.3 ms, of their frame, and only 1% lie within 2.3 ms of the midpoint between two frames.
/// - Offsets are moved less, so they do sit on a grid of 23.22 ms: half of them lie within 1.2 ms of a frame, as do 62% of the sustain presses and nearly every change of the soft pedal.
/// - Onsets are unbiased, and 90% are within 9 ms of the played ones; the median error is 3.2 ms, rising to about 4.5 ms below C2 and under velocity 30. The time between two successive onsets is off by 5.5 ms (standard deviation).
/// - Before Transkun 1.3.0, onsets and offsets were moved by a sigmoid of the model's output, which saturates at half a frame: almost half of the onsets lie within about a millisecond of the midpoint between two frames, on a grid of 23.22 ms, and the median error is 4.2 ms.
///
/// ### Chords
///
/// - Of two notes struck together, within 1 ms, 62% get onsets less than 2 ms apart, though almost none get exactly the same onset, and 4% end up more than 10 ms apart, nearly always because the two fall into neighboring frames.
/// - Two notes played 5 to 10 ms apart keep their order 94% of the time, 98% of the time when played 10 to 15 ms apart, and 82% when played 2 to 5 ms apart. Notes played 20 to 30 ms apart come out 24 ms apart in the median, against 25 ms played.
///
/// ### Offsets and Durations
///
/// - Offsets follow the release of the key, not the pedal: the median error is 13 ms, and 80% are within 50 ms. A note held by the pedal still ends where its key was released.
/// - Releases come out rougher than strikes: of two keys released together, within 1 ms, 31% get offsets less than 2 ms apart, and a third end up more than 20 ms apart.
/// - Successive notes on a key keep the gap the pianist left between them; a note is almost never cut short by the next one.
/// - All but 0.05% of the notes last at least a frame.
///
/// ### Velocity
///
/// - Velocities follow the played ones closely: a transcribed velocity is about 0.97 times the played one plus 2, with a mean absolute error of 2.1 and a correlation of 0.99. Accents survive: against the mean of the notes within a second on either side, a velocity correlates at 0.97 with the played one, and a difference of more than 10 has the right sign 99.9% of the time.
/// - Velocities range from 3 to 126, and 98% lie in 25...101.
///
/// ### Pedals
///
/// - The sustain pedal is written as fully down or fully up, CC 64 at 127 or 0, so half-pedaling is lost. 96% of the presses are real, 88% of the real ones are found within 100 ms, and the pedal is in the right state 96% of the time. From the 10th to the 90th percentile, presses are from 37 ms early to 26 ms late, and releases from 13 ms early to 20 ms late.
/// - The soft pedal is written too, CC 67 at 127 or 0, but roughly: it is in the right state 85% of the time, yet only a third of its presses are within 100 ms of a real one.
///
/// ### Errors
///
/// - 99.8% of the notes were played. The others are quieter, with a median velocity of 49 against 67, and are mostly a second detection of a key that was just played (half of them) or the octave above or below a played note (a fifth). Under velocity 20, 3% of the notes were not played.
/// - 96% of the played notes are found. The ones missed are quiet: 32% of the notes played under velocity 20 are found, 73% at 20...29 and 89% at 30...39. A key struck again 50 to 80 ms after its previous strike is found 67% of the time, and sooner than that 25%. The outer octaves lose a little, with 90% found under C2 and 92% from C7 on. Dense chords lose little.
///
/// ### Tempo and Meter
///
/// - The file is written at 120 BPM in 4/4, whatever the music: a beat is half a second of the recording, and neither the tempo nor the time signature says anything about the meter.
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

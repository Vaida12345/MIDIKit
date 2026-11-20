//
//  AnalysisProfile+PT.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


/// The profile for notes that PianoTranscription transcribed.
///
/// **Note offsets cannot be relied on.** They include the ring of the sound and the sustain pedal, in a way that follows neither the release of the key nor the pedal events the model writes: a median note lasts about 300 ms. Chord formation therefore never looks at them. (The glissando check, which every arbiter shares, does look at how long notes last, and so finds a glissando in such output only when the model cut its notes short.)
///
/// Onset times sit on a weak grid of 10 ms, too blurred to use, so the gap between two close notes is used as it is. Velocities are meaningful, and chord formation uses them.
///
/// Artifacts are removed with ``GenericProfile/removingArtifacts(from:threshold:proximityThreshold:)``, which was written for the stray quiet notes this transcriber produces.
public struct PianoTranscriptionProfile: AnalysisProfile {

    /// Creates the PianoTranscription profile.
    public init() {

    }

    /// Groups the notes of `track` into chords with ``ChordArbiter/pianoTranscription``.
    public func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.pianoTranscription.formChords(in: track)
    }

}


extension AnalysisProfile where Self == PianoTranscriptionProfile {

    /// The profile for notes that PianoTranscription transcribed.
    public static var pianoTranscription: PianoTranscriptionProfile {
        PianoTranscriptionProfile()
    }

}


extension ChordArbiter {

    /// The arbiter for notes that PianoTranscription transcribed.
    ///
    /// The offsets cannot be relied on (they include the ring of the sound), so the release is left out, and the timing has no grid that helps. What it adds to ``generic`` is the velocity of the second note, which this transcriber reports on the scale of a MIDI keyboard.
    ///
    /// Tuned on the transcription of the MAESTRO dataset. The constants of the generic arbiter were already right for this input: retuning them gained 0.03 of the tuning objective, and not in every fold. The velocity cue gained 0.23 (more chords found exactly, fewer gray-zone pairs wrong), in all four folds. A weak grid model, a cap on the span of a chord and a constraint on runs gained nothing.
    public static let pianoTranscription = ChordArbiter(
        stepLimit: 25,
        octaveLimit: 54.45,
        otherLimit: 44.1,
        previousWeight: 0.37,
        nextWeight: 0.21,
        isolationKnee: 2,
        isolationCap: 8,
        isolationFloor: 0.1,
        densityWeight: -0.18,
        densityCenter: 4,
        densityWindow: 150,
        releaseWeight: 0,
        releaseScale: 15,
        releaseCap: 3,
        velocityWeight: 0.1,
        velocityCenter: 64,
        velocityCap: 4,
        maximumSize: 24
    )

}

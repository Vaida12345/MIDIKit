//
//  TranscriptionAlgorithm.swift
//  MIDIKit
//
//  Created by Vaida on 11/9/26.
//

import Foundation


/// The algorithm that transcribed audio into the MIDI that is being processed.
///
/// A transcription algorithm leaves traces in what it writes: the grid its timing sits on, how it treats the sustain pedal, how loosely it times the notes of a chord, how it scales velocity. APIs that take an `optimizeFor` argument use those traces when they know the algorithm, and fall back to generic behavior when the argument is `nil`. Knowing the algorithm also tells what not to use: a trace that cannot be trusted is left out.
public enum TranscriptionAlgorithm: String, CaseIterable, Hashable, Sendable, Codable {

    /// [Transkun](https://github.com/Yujia-Yan/Transkun).
    ///
    /// Onset times sit on a grid of about 23 ms (1024 samples at 44.1 kHz), so the gap between two close notes comes in steps. Note offsets follow the release of the key, not the sustain pedal.
    case transkun

    /// PianoTranscription, the transcriber that ``IndexedContainer/normalize(preserve:optimizeFor:)`` is written for.
    ///
    /// **Note offsets cannot be relied on.** They include the ring of the sound and the sustain pedal, in a way that follows neither the release of the key nor the pedal events the model writes: a median note lasts about 300 ms. Chord formation therefore never looks at them. (The glissando check, which every chord algorithm shares, does look at how long notes last, and so finds a glissando in such output only when the model cut its notes short.)
    ///
    /// Onset times sit on a weak grid of 10 ms, too blurred to use, so the gap between two close notes is used as it is. Velocities are meaningful, and chord formation uses them: a note that starts shortly after another and is much quieter than a typical note is, more often than not, a note of the other's chord.
    case pianoTranscription

}

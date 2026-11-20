//
//  AnalysisProfile+PT.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


/// The profile for notes that PianoTranscription transcribed.
///
/// Chords are formed with ``ChordArbiter/pianoTranscription`` and downbeats found with ``DownbeatTracker/pianoTranscription``, which both leave the offsets out; the arbiter weighs the velocities instead. (The glissando check, which every arbiter shares, does look at how long notes last, and so finds a glissando in such output only when the model cut its notes short.) Artifacts are removed with ``GenericProfile/removingArtifacts(from:threshold:proximityThreshold:)``, written for the ghost repetitions described under Errors.
///
/// ## Shape of the Output
///
/// These figures were measured on the 1,276 performances of MAESTRO v3, against the MIDI that the piano recorded. A played note counts as found when the transcription has a note on its key whose onset is within 50 ms of it. Accuracy figures come from the 177 performances of the test split, as the model was trained on the others; the other figures come from all of them.
///
/// ### Timing
///
/// - Notes are decoded on frames of 10 ms, 100 a second from audio at 16 kHz, and each onset is moved by at most half a frame, towards the peak of the model's onset curve. The move leans towards half a frame either way, which makes a weak grid of 10 ms, too blurred to use.
/// - Onsets are 3 ms late on average, in every register and at every velocity, and 90% are from 8 ms early to 13.5 ms late; the median error is 4.6 ms. The time between two successive onsets is off by 7 ms (standard deviation).
///
/// ### Chords
///
/// - Of two notes struck together, within 1 ms, 6% get exactly the same onset, and 59% onsets less than 2 ms apart. 2% end up more than 10 ms apart.
/// - Two notes played 5 to 10 ms apart keep their order 86% of the time and swap 13% of the time, and keep it 95% of the time when played 10 to 15 ms apart.
///
/// ### Offsets and Durations
///
/// - **Offsets follow the sound, not the key**: a note ends where the model hears it fade, one frame before its key is struck again, or after 6 s. The median note lasts 300 ms where the played one lasts 90 ms, and only a third of the offsets are within 50 ms of the release of the key, which therefore cannot be read from them.
/// - An offset rather tells how long the note rings: against the release of the key, held for as long as the model's own pedal stays down, the median error is 0 and 65% of the offsets are within 50 ms. 18% end more than 200 ms early, where the sound faded while the pedal was down.
/// - A note still sounding when its key is struck again ends one frame before the new onset, 5 to 14 ms before it from the 10th to the 90th percentile. 28% of the gaps between successive notes on a key are under 20 ms, against 0.2% in the performances; such a note was cut, not released.
/// - No note lasts more than 6 s, and 0.1% are cut there. About a third of the offsets fall exactly on a frame: those of the notes that faded or were cut.
///
/// ### Velocity
///
/// - A transcribed velocity is about 0.94 times the played one plus 6: 2.4 too high on average, and 7 too high for the notes played under 30. The mean absolute error is 3.8, and the correlation 0.97. Accents survive: against the mean of the notes within a second on either side, a velocity correlates at 0.93 with the played one, and a difference of more than 10 has the right sign 99.5% of the time.
/// - Velocities range from 3 to 121, and 98% lie in 28...104.
///
/// ### Pedals
///
/// - Only the sustain pedal is written, as fully down or fully up, CC 64 at 127 or 0, so half-pedaling is lost. 87% of the presses are real, 87% of the real ones are found within 100 ms, and the pedal is in the right state 94% of the time.
/// - A press is placed where the model's pedal curve first rises over its threshold, so presses are about 12 ms late in the median, and from 30 ms early to 67 ms late from the 10th to the 90th percentile. Releases are from 16 ms early to 22 ms late, and always fall exactly on a frame. A press, or a gap between two presses, can be as short as 5 ms.
///
/// ### Errors
///
/// - 98.7% of the notes were played. The others are quieter, with a median velocity of 56 against 69: a fifth of the notes under velocity 20 were not played, 9% of those at 20...29 and 4% of those at 30...39. A fifth of them are the octave above a played note.
/// - Half of them are ghost repetitions. A ghost starts within 20 ms after a played note on its key ends, which it cut short, at about 82% of that note's velocity in the median; at a median velocity of 57, it is not always quiet. The pattern alone does not mark a ghost, though: 97% of the notes that start right after a note on their key ends are real re-strikes, at about the velocity of the note they cut (a median ratio of 1.0).
/// - 93% of the played notes are found. The ones missed are quiet, with 25% of the notes played under velocity 20 found, 64% at 20...29 and 84% at 30...39; in the outer octaves, with 78% found under C2 and 80% from C7 on; in dense chords, with about 85% of the notes found in chords of seven or eight; or fast repetitions, with 57% of the strikes 50 to 80 ms after the previous one on their key found, and 19% of those sooner.
///
/// ### Tempo and Meter
///
/// - The file is written at 120 BPM in 4/4, whatever the music: a beat is half a second of the recording, and neither the tempo nor the time signature says anything about the meter.
public struct PianoTranscriptionProfile: AnalysisProfile {

    /// Creates the PianoTranscription profile.
    public init() {

    }

    /// Groups the notes of `track` into chords with ``ChordArbiter/pianoTranscription``.
    public func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.pianoTranscription.formChords(in: track)
    }
    
    /// Finds the downbeats of `track` with ``DownbeatTracker/pianoTranscription``.
    public func downbeats(in track: IndexedTrack, prior: [Double]) -> [Double] {
        DownbeatTracker.pianoTranscription.downbeats(in: track, prior: prior)
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


extension DownbeatTracker {
    
    /// PianoTranscription: the offsets cannot be relied on (they include the ring of the sound), so they are never read.
    ///
    /// Tuned on the PianoTranscription transcriptions of the MAESTRO audio. The duration weight is the one it was tuned with, and has no effect.
    public static let pianoTranscription = DownbeatTracker(
        bassWeight: 1.4,
        massWeight: 0.3,
        durationWeight: 0.7,
        chromaWeight: 0.6,
        wideChromaWeight: 0.6,
        pedalWeight: 0.3,
        gapWeight: 0.3,
        readsOffsets: false,
        tempoChangeCost: 30,
        beatFloor: 0.028,
        offBeatWeight: 0.6,
        downbeatGain: 1.6,
        downbeatCost: 0.7,
        meterChangeCost: 11.2,
        beatRegionDivisor: 14,
        tripleMeterBonus: 0.2,
        quadrupleMeterBonus: 0.4
    )
    
}

//
//  VelocityTransfer.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


/// The constants of ``IndexedTrack/applyingVelocities(from:warp:)``.
///
/// Tuned on about 200 pieces of the ASAP dataset, as the sheet, against the transcriptions of their MAESTRO recordings by transkun and by PianoTranscription, each cut to the performance and whole. The truth is the velocity of each sheet note's partner in the exact MAESTRO performance. Both transcribers gave the same optimum, within 0.05 velocity units, so one set serves every source. On 93 other pieces, a transferred velocity is off by 2.05 on average for transkun and 4.08 for PianoTranscription, against 1.80 and 3.80 when the true partner is known; most of what remains is the transcriber's own error.
enum VelocityTransfer {
    
    /// How far in beats a note's warped onset may be from the onset of its partner on the same key. Anything from 0.1 to 0.4 does as well.
    static let matchWindow = 0.15
    
    /// The spread in beats of the weights by time, for a note without a partner.
    static let timeScale = 0.5
    
    /// The spread in semitones of the weights by pitch, for a note without a partner.
    static let pitchScale = 3.0
    
    /// The velocity subtracted from an estimate for a note without a partner.
    ///
    /// A transcriber misses quiet notes far more often than loud ones: the notes it missed were played at 44 to 51 on average, while their neighbors suggest 63 to 71. With this offset, the error on those notes falls from about 20 to 13.
    static let missedNoteOffset = 15.0
    
    /// The factor that widens both spreads when no performance note lies within reach of a note without a partner.
    static let fallbackFactor = 4.0
    
    /// The total weight under which an estimate is not trusted.
    static let minimumWeight = 1e-6
    
}

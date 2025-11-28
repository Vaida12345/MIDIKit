//
//  KeySignature.swift
//  MIDIKit
//
//  Created by Vaida on 2025-11-16.
//


extension IndexedContainer {
    
    /// The set of sharps or flats placed after the clef to show which notes are altered throughout the piece.
    public struct KeySignature: Hashable, Sendable, Codable {
        
        /// pitches expressed in index form.
        ///
        /// The scale degrees (0–11) of notes altered by this key signature,
        /// listed in the conventional order sharps or flats are applied.
        /// Each value represents a pitch class using semitone indices
        /// relative to C = 0.
        public let pitches: [Int]
        
        public let accidental: Accidental
        
        public init(pitches: [Int], accidental: Accidental) {
            self.pitches = pitches
            self.accidental = accidental
        }
        
        
        public enum Accidental: Int, CaseIterable, Hashable, Sendable, Codable {
            case flat = -1
            case sharp = 1
            case neutral = 0
        }
    }
    
}


extension IndexedContainer.KeySignature: CaseIterable {
    public static let natural = IndexedContainer.KeySignature(pitches: [], accidental: .neutral)
    
    public static let flats1 = IndexedContainer.KeySignature(pitches: [11], accidental: .flat)
    public static let flats2 = IndexedContainer.KeySignature(pitches: [11, 4], accidental: .flat)
    public static let flats3 = IndexedContainer.KeySignature(pitches: [11, 4, 9], accidental: .flat)
    public static let flats4 = IndexedContainer.KeySignature(pitches: [11, 4, 9, 2], accidental: .flat)
    public static let flats5 = IndexedContainer.KeySignature(pitches: [11, 4, 9, 2, 7], accidental: .flat)
    public static let flats6 = IndexedContainer.KeySignature(pitches: [11, 4, 9, 2, 7, 0], accidental: .flat)
    public static let flats7 = IndexedContainer.KeySignature(pitches: [11, 4, 9, 2, 7, 0, 5], accidental: .flat)
    
    public static let sharps1 = IndexedContainer.KeySignature(pitches: [5], accidental: .sharp)
    public static let sharps2 = IndexedContainer.KeySignature(pitches: [5, 0], accidental: .sharp)
    public static let sharps3 = IndexedContainer.KeySignature(pitches: [5, 0, 7], accidental: .sharp)
    public static let sharps4 = IndexedContainer.KeySignature(pitches: [5, 0, 7, 2], accidental: .sharp)
    public static let sharps5 = IndexedContainer.KeySignature(pitches: [5, 0, 7, 2, 9], accidental: .sharp)
    public static let sharps6 = IndexedContainer.KeySignature(pitches: [5, 0, 7, 2, 9, 4], accidental: .sharp)
    public static let sharps7 = IndexedContainer.KeySignature(pitches: [5, 0, 7, 2, 9, 4, 11], accidental: .sharp)
    
    public static let allCases: [IndexedContainer.KeySignature] = [
        flats1, flats2, flats3, flats4, flats5, flats6, flats7,
        .natural,
        sharps1, sharps2, sharps3, sharps4, sharps5, sharps6, sharps7
    ]
}


extension IndexedContainer {
    
    /// Infers the most likely key signature for the container’s contents.
    ///
    /// Instead of counting how many notes fit a given scale, the algorithm
    /// looks at **semitone motions between successive chords** and asks:
    ///
    /// *In which key do we most often see the characteristic half–steps
    /// between scale degrees 3–4 and 7–1?*
    ///
    /// Concretely:
    /// - The container is first converted to a sequence of `Chord` values via
    ///   `self.chords()`, ordered by onset.
    /// - For each pair of successive chords, all note pairs
    ///   `(note in chordₙ, note in chordₙ₊₁)` are inspected.
    /// - Whenever two notes are a semitone apart (±1 MIDI pitch), a counter
    ///   is incremented for the lower pitch class (0–11).
    /// - For each candidate major key (C♭ … C♯) the algorithm knows which two
    ///   pitch–class semitones correspond to scale degrees 3–4 and 7–1 in
    ///   that key, and sums their counts to form a score.
    /// - The key with the highest score is selected; in case of a tie, the
    ///   key with fewer accidentals (closer to C major) is preferred.
    ///
    /// Notes:
    /// - The result is a **key signature** (e.g. “2 flats”) rather than a
    ///   full tonal label (“B♭ major” vs “G minor”). Relative major/minor
    ///   keys share the same signature and are not distinguished here.
    /// - The detection is driven by melodic half–step behavior and works
    ///   best for tonal, reasonably long excerpts. Highly chromatic,
    ///   atonal, or very short passages may yield less meaningful results.
    ///
    /// - Returns: An `IndexedContainer.KeySignature` representing the inferred
    ///   key signature, or `.natural` if no informative semitone transitions
    ///   are found.
    public func keySignature() -> IndexedContainer.KeySignature {
        let chords = self.chords()
        guard chords.count >= 2 else {
            return .natural
        }
        
        // 1. Count semitone transitions per pitch class (0–11),
        //    using the LOWER pitch of the semitone pair, like MuseScore.
        var counts = Array(repeating: 0, count: 12)
        
        for i in 0 ..< chords.count - 1 {
            let chord1 = chords[i]
            let chord2 = chords[i + 1]
            
            // chord contents are [ReferenceNote]
            for note1 in chord1 {
                for note2 in chord2 {
                    // Assuming `note` is a MIDI pitch (UInt8)
                    let p1 = Int(note1.note)
                    let p2 = Int(note2.note)
                    let diff = abs(p2 - p1)
                    
                    if diff == 1 {
                        let lower = Swift.min(p1, p2) % 12
                        counts[lower] += 1
                    }
                }
            }
        }
        
        // If we saw no semitone transitions at all, this heuristic has nothing to work with.
        // Fall back to a neutral key signature.
        if counts.allSatisfy({ $0 == 0 }) {
            return .natural
        }
        
        // 2. Map MuseScore's major keys to your KeySignature definitions.
        //
        // Each tuple is (keySignature, index for 3–4, index for 7–1),
        // where indices refer to the LOWER pitch class (0–11) of the semitone.
        //
        // Order mirrors MuseScore:
        //   C♭, G♭, D♭, A♭, E♭, B♭, F, C, G, D, A, E, B, F♯, C♯
        // matched to flats7…flats1, natural, sharps1…sharps7.
        let candidates: [(IndexedContainer.KeySignature, Int, Int)] = [
            (.flats7,   3, 10), // C♭ major
            (.flats6,  10,  5), // G♭ major
            (.flats5,   5,  0), // D♭ major
            (.flats4,   0,  7), // A♭ major
            (.flats3,   7,  2), // E♭ major
            (.flats2,   2,  9), // B♭ major
            (.flats1,   9,  4), // F major
            (.natural,  4, 11), // C major
            (.sharps1, 11,  6), // G major
            (.sharps2,  6,  1), // D major
            (.sharps3,  1,  8), // A major
            (.sharps4,  8,  3), // E major
            (.sharps5,  3, 10), // B major
            (.sharps6, 10,  5), // F♯ major
            (.sharps7,  5,  0)  // C♯ major
        ]
        
        // 3. Choose the key with maximum semitone‑pattern score.
        //    On ties, prefer fewer accidentals (like MuseScore’s tie‑breaker).
        var bestKey = IndexedContainer.KeySignature.natural
        var bestScore = Int.min
        
        for (keySig, i1, i2) in candidates {
            let score = counts[i1] + counts[i2]
            
            if score > bestScore {
                bestScore = score
                bestKey = keySig
            } else if score == bestScore {
                // Tie‑breaker: fewer accidentals
                let accBest = bestKey.pitches.count
                let accThis = keySig.pitches.count
                if accThis < accBest {
                    bestKey = keySig
                }
            }
        }
        
        return bestKey
    }
    
}

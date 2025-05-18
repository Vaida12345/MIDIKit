//
//  Hands.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-18.
//

import Foundation


public enum Hand {
    case left
    case right
}


extension IndexedContainer {
    
    public func assignHands() {
        guard !self.isEmpty else { return }
        
//        • Pitch proximity: Consecutive notes that are close in pitch are likely to belong to the same hand. Large leaps tend to imply hand changes or chord boundaries.
//        • Time adjacency: Consecutive notes in very quick succession (e.g., a fast scale) are often played by the same hand—unless the pitch jump is extremely large.
//        • Chord grouping: Notes that sound simultaneously (or nearly simultaneously) and form a chord typically belong to one hand if they are in a contiguous pitch region. If chord tones span widely (like a 10th or more between them), it may suggest a split between hands.
//        • Physical constraints: Pianists rarely cross their arms for very long passages. If your ML output tries to keep the left hand consistently above the right in pitch, that’s usually non-idiomatic. A cost function can penalize extreme or persistent crossing.
        
        // MARK: - Cost functions
        // All cost function should be normalized between 0 and 1, with 0 being no cost.
        
        /// Hand range priors
        ///
        /// By default, the left hand is more comfortable below a certain pitch zone while the right hand is more comfortable above it. But this boundary is not fixed; it can shift or be overridden if other heuristics suggest it.
        func handRangeCost(note: MIDINote, hand: Hand, boundary: UInt8) -> Double {
            let spreadFactor: Double = 7
            let distance = (Int(note.note) - Int(boundary)) * (hand == .right ? 1 : -1)
            return -tanh(Double(distance) / spreadFactor) / 2 + 0.5
        }
        
//        /// The transition cost form moving from prev note to curr note.
//        func transitionCost(from prevNote: ReferenceNote, hand prevHand: Hand, to currNote: ReferenceNote, hand currHand: Hand) -> Double {
//            
//        }
        
        
        // MARK: - Computation
        let average = RunningAverage(combinedNotes: self.contents)
        
        for (index, note) in self.contents.enumerated() {
            let average = average[at: note.onset]!
            let cost = handRangeCost(note: note, hand: .left, boundary: average.note)
            self.contents[index].velocity = UInt8(cost * 127)
        }
    }
    
}

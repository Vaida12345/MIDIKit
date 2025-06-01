//
//  Hands.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-18.
//

import Foundation
import Essentials


fileprivate enum Hand: CaseIterable, CustomStringConvertible {
    case left
    case right
    
    var rightHandness: Double {
        self.isRightHand ? 1.0 : -1.0
    }
    
    var isRightHand: Bool {
        self == .right
    }
    
    var description: String {
        switch self {
        case .left: "left"
        case .right: "right"
        }
    }
}


fileprivate struct HandCost {
    
    var left: Double = 0
    
    var right: Double = 0
    
    
    var minCostHand: Hand {
        if left < right {
            return .left
        } else {
            return .right
        }
    }
    
    
    subscript(_ hand: Hand) -> Double {
        get {
            switch hand {
            case .left: self.left
            case .right: self.right
            }
        }
        set {
            switch hand {
            case .left: self.left = newValue
            case .right: self.right = newValue
            }
        }
    }
    
}

fileprivate struct HandBacktrack {
    
    var left: Hand = .left
    
    var right: Hand = .left
    
    
    subscript(_ hand: Hand) -> Hand {
        get {
            switch hand {
            case .left: self.left
            case .right: self.right
            }
        }
        set {
            switch hand {
            case .left: self.left = newValue
            case .right: self.right = newValue
            }
        }
    }
    
}



extension IndexedContainer {
    
    public func assignHands() {
        guard !self.isEmpty else { return }
        
        // MARK: - Cost functions
        // All cost function should be normalized between 0 and 1, with 0 being no cost.
        
        /// Hand range priors
        ///
        /// By default, the left hand is more comfortable below a certain pitch zone while the right hand is more comfortable above it. But this boundary is not fixed; it can shift or be overridden if other heuristics suggest it.
        func handRangeCost(note: ReferenceNote, hand: Hand, boundary: UInt8, span: UInt8) -> Double {
            let spreadFactor: Double = 7
            let distance = Double(Int(note.note) - Int(boundary)) * hand.rightHandness
            return -tanh(distance / spreadFactor) / 2 + 0.5
        }
        
        /// The transition cost form moving from prev note to curr note.
        func transitionCost(
            from prevNote: ReferenceNote, hand prevHand: Hand,
            to currNote: ReferenceNote, hand currHand: Hand,
            boundary: UInt8, span: UInt8
        ) -> Double {
            var cost = 0.0
            
            let pitchDifference = Double(currNote.note) - Double(prevNote.note)
            let pitchDistance = abs(pitchDifference)
            let onsetDistance = Double(currNote.onset) - Double(prevNote.onset)
            
            // Pitch proximity: Consecutive notes that are close in pitch are likely to belong to the same hand. Large leaps tend to imply hand changes or chord boundaries.
            if prevHand == currHand {
                if pitchDistance <= 13 {
                    cost += 0
                } else {
                    if pitchDistance <= 16 {
                        cost += linearInterpolate(pitchDistance, in: 13...16, to: 0.5...1)
                    } else {
                        cost += 2 // unlikely
                    }
                }
            } else {
                cost += 0.5 // cross hand cost
                
                let diff = pitchDifference * currHand.rightHandness
                if diff > 0 {
                    cost += 0
                } else if diff == 0 {
                    cost += 0.9 // unlikely, two hand playing the same note?
                } else if diff < -13 {
                    cost += 0.5 // cross hand
                } else {
                    cost += 1.5 // unlikely, two hand playing at the same place?
                }
            }
            
            return cost
        }
        
        
        // MARK: - Computation
        let average = self.runningAverage()
        
//        var dp = Array(repeating: [String: Double](), count: groups.count)
//        var backtrack = Array(repeating: [String: String](), count: groups.count)
        var costs = Array(repeating: HandCost(), count: self.contents.count)
        var backtrack = Array(repeating: HandBacktrack(), count: self.contents.count)
        let contents = Chord.makeSingleHandedChords(from: self)
        
        
        let initialAverage = average[at: contents.first!.leadingOnset]!
        for hand in Hand.allCases {
            let note = contents[0]
            let cost = note.contents.reduce(0) { $0 + handRangeCost(note: $1, hand: hand, boundary: initialAverage.note, span: initialAverage.span) }
            costs[0][hand] = cost
        }
        
        for i in 1..<contents.count {
            let prev = contents[i - 1]
            let curr = contents[i]
            let average = average[at: curr.leadingOnset]!
            
            for hand in Hand.allCases {
                var bestCost = Double.infinity
                var bestPrevHand: Hand = .left
                
                for prevHand in Hand.allCases {
                    let cost = curr.contents.reduce(0) { $0 + handRangeCost(note: $1, hand: hand, boundary: initialAverage.note, span: initialAverage.span) }
                    let transCost = transitionCost(from: prev.contents.last!, hand: prevHand, to: curr.contents.first!, hand: hand, boundary: average.note, span: average.span)
                    let totalCost = costs[i-1][prevHand] + cost + transCost
                    
                    if totalCost < bestCost {
                        bestCost = totalCost
                        bestPrevHand = prevHand
                    }
                }
                
                costs[i][hand] = bestCost
                backtrack[i][hand] = bestPrevHand
            }
        }
        
        
        var lastHand = costs.last!.minCostHand
        for note in contents[contents.count - 1] {
            note.velocity = lastHand.isRightHand ? 127 : 0
        }
        
        for i in stride(from: contents.count - 1, through: 0, by: -1) {
            let prevHand = backtrack[i][lastHand]
            lastHand = prevHand
            for note in contents[i] {
                note.velocity = lastHand.isRightHand ? 127 : 0
            }
        }
    }
    
}

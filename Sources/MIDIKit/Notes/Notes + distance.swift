//
//  Notes + distance.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import Essentials


extension MIDINotes {
    
    /// A difference score to `rhs` based on the timing of notes.
    ///
    /// The result can be interpreted as the sum of difference in timing. When a key is missing, the penalty is 10 seconds.
    ///
    /// The duration has a weight of 1/10 compared to onset.
    ///
    /// - Returns: The distance in seconds.
    public func distance(to rhs: MIDINotes, missingPenalty: Double = 10) -> Double {
        final class Matching: CustomStringConvertible, @unchecked Sendable {
            let note: MIDINote
            var isMatched: Bool
            let missingPenalty: Double
            
            var description: String {
                self.note.description
            }
            
            func distance(to matching: Matching) -> Double {
                clamp(abs(self.note.onset - matching.note.onset) + abs(self.note.duration - matching.note.duration) / 10, max: 10)
            }
            
            init(note: MIDINote, missingPenalty: Double) {
                self.note = note
                self.isMatched = false
                self.missingPenalty = missingPenalty
            }
        }
        
        var lhsGroup : [UInt8 : [Matching]] = [:]
        for note in self.contents {
            lhsGroup[note.note, default: []].append(Matching(note: note, missingPenalty: missingPenalty))
        }
        
        var rhsGroup : [UInt8 : [Matching]] = [:]
        for note in rhs.contents {
            rhsGroup[note.note, default: []].append(Matching(note: note, missingPenalty: missingPenalty))
        }
        
        
        let sums = (UInt8.min ... UInt8.max).map { note in
            var sum: Double = 0
            
            let lhsNotes = lhsGroup[note, default: []].sorted(on: \.note.onset, by: <)
            var _lhsIterator = lhsNotes.makeIterator()
            var _lhs: Matching? = nil
            func lhs() -> Matching? {
                if let _lhs,
                   !_lhs.isMatched {
                    return _lhs
                } else {
                    _lhs = _lhsIterator.next()
                    guard _lhs != nil else { return nil }
                    return lhs()
                }
            }
            
            let rhsNotes = rhsGroup[note, default: []].sorted(on: \.note.onset, by: <)
            var _rhsIterator = rhsNotes.makeIterator()
            var _rhs: Matching? = nil
            func rhs() -> Matching? {
                if let _rhs,
                   !_rhs.isMatched {
                    return _rhs
                } else {
                    _rhs = _rhsIterator.next()
                    guard _rhs != nil else { return nil }
                    return rhs()
                }
            }
            
            var lhsMatchedIndex = 0
            var rhsMatchedIndex = 0
            
            while let lhs = lhs(), let rhs = rhs() {
                // best match for lhs
                var lhsBestMatch: Matching?
                var lhsBestDistance: Double = .infinity
                
                var lhsMatchingIndex = lhsMatchedIndex
                while lhsMatchingIndex < rhsNotes.count {
                    let distance = rhsNotes[lhsMatchingIndex].distance(to: lhs)
                    if distance < lhsBestDistance {
                        lhsBestDistance = distance
                        lhsBestMatch = rhsNotes[lhsMatchingIndex]
                    }
                    if rhsNotes[lhsMatchingIndex].note.onset > lhs.note.onset {
                        break
                    }
                    
                    lhsMatchingIndex &+= 1
                }
                
                // best match for rhs
                var rhsBestMatch: Matching?
                var rhsBestDistance: Double = .infinity
                
                var rhsMatchingIndex = rhsMatchedIndex
                while rhsMatchingIndex < lhsNotes.count {
                    let distance = lhsNotes[rhsMatchingIndex].distance(to: rhs)
                    if distance < rhsBestDistance {
                        rhsBestDistance = distance
                        rhsBestMatch = lhsNotes[rhsMatchingIndex]
                    }
                    if lhsNotes[rhsMatchingIndex].note.onset > rhs.note.onset {
                        break
                    }
                    
                    rhsMatchingIndex &+= 1
                }
                
                if lhsBestDistance <= rhsBestDistance {
                    // choose left
                    lhsBestMatch?.isMatched = true
                    lhs.isMatched = true
                    sum += lhsBestDistance
                    lhsMatchedIndex += 1
                } else if lhsBestDistance > rhsBestDistance {
                    // choose right
                    rhsBestMatch?.isMatched = true
                    rhs.isMatched = true
                    sum += rhsBestDistance
                    rhsMatchedIndex += 1
                }
            }
            
            // check remaining
            while let lhs = lhs() {
                lhs.isMatched = true
                sum += missingPenalty
            }
            while let rhs = rhs() {
                rhs.isMatched = true
                sum += missingPenalty
            }
            
            return sum
        }
        
        return sums.reduce(0, +) 
    }
    
}

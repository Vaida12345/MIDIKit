//
//  VelocityTransfer+Match.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


extension VelocityTransfer {
    
    /// A possible pair of a sheet note and a performance note on the same key.
    struct Candidate: Comparable {
        
        /// How far apart the warped onset of the sheet note and the onset of the performance note are, in beats.
        var distance: Double
        
        /// The position of the sheet note in the sheet's lane members.
        var sheet: Int
        
        /// The position of the performance note in the performance's lane members.
        var performance: Int
        
        static func < (lhs: Candidate, rhs: Candidate) -> Bool {
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.sheet != rhs.sheet { return lhs.sheet < rhs.sheet }
            return lhs.performance < rhs.performance
        }
        
    }
    
    
    /// Pairs the notes of a sheet with the notes of a performance on the same key, one to one.
    ///
    /// On each key, every sheet note and performance note whose onsets are less than `window` apart, after the sheet's onsets are warped, are candidates. The closest candidates are taken first, and a candidate is taken when neither of its notes is taken yet. Ties go to the earlier sheet note, then to the earlier performance note, so the result is deterministic.
    ///
    /// - Parameters:
    ///   - onsets: The onset of each sheet note, warped into the beats of the performance, indexed like the sheet's notes. Within a key, they must be in the order of the sheet's notes, which a warp keeps.
    ///   - sheet: The lanes of the sheet.
    ///   - performance: The lanes of the performance.
    ///   - window: How far apart in beats the onsets of a pair may be, exclusive.
    ///
    /// - Returns: For each sheet note, the index in the performance's notes of its partner, or `-1`.
    ///
    /// - Complexity: O(*n* + *m* + *c* log *c*), where *n* and *m* are the numbers of notes of the sheet and the performance, and *c* the number of candidates, a few for each note.
    static func partners(onsets: [Double], sheet: IndexedTrack.Lanes, performance: IndexedTrack.Lanes, window: Double) -> [Int] {
        var partners = [Int](repeating: -1, count: onsets.count)
        var sheetTaken = [Bool](repeating: false, count: sheet.members.count)
        var performanceTaken = [Bool](repeating: false, count: performance.members.count)
        var candidates: [Candidate] = []
        
        onsets.withUnsafeBufferPointer { onsets in
            sheet.members.withUnsafeBufferPointer { sheetMembers in
                performance.members.withUnsafeBufferPointer { performanceMembers in
                    performance.notes.withUnsafeBufferPointer { performanceNotes in
                        var lane = 0
                        while lane < 88 {
                            let sheetStart = sheet.starts[lane]
                            let sheetEnd = sheet.starts[lane &+ 1]
                            let performanceStart = performance.starts[lane]
                            let performanceEnd = performance.starts[lane &+ 1]
                            defer { lane &+= 1 }
                            guard sheetStart < sheetEnd, performanceStart < performanceEnd else { continue }
                            
                            // Both lanes are sorted by onset, so the first performance note in reach only moves forward.
                            candidates.removeAll(keepingCapacity: true)
                            var low = performanceStart
                            var x = sheetStart
                            while x < sheetEnd {
                                let time = onsets[sheetMembers[x]]
                                while low < performanceEnd && performanceNotes[performanceMembers[low]].onset <= time - window {
                                    low &+= 1
                                }
                                var y = low
                                while y < performanceEnd {
                                    let distance = performanceNotes[performanceMembers[y]].onset - time
                                    if distance >= window { break }
                                    candidates.append(Candidate(distance: Swift.abs(distance), sheet: x, performance: y))
                                    y &+= 1
                                }
                                x &+= 1
                            }
                            
                            candidates.sort()
                            for candidate in candidates where !sheetTaken[candidate.sheet] && !performanceTaken[candidate.performance] {
                                sheetTaken[candidate.sheet] = true
                                performanceTaken[candidate.performance] = true
                                partners[sheetMembers[candidate.sheet]] = performanceMembers[candidate.performance]
                            }
                        }
                    }
                }
            }
        }
        
        return partners
    }
    
}

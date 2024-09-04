//
//  Notes.swift
//  MIDIKit
//
//  Created by Vaida on 8/26/24.
//

import Stratum
import OSLog


public struct MIDINotes: RandomAccessCollection, Sendable, Equatable {
    
    var notes: [MIDITrack.Note]
    
    public var startIndex: Int {
        self.notes.startIndex
    }
    
    public var endIndex: Int {
        self.notes.endIndex
    }
    
    public mutating func append(contentsOf: MIDINotes) {
        self.notes.append(contentsOf: contentsOf.notes)
    }
    
    public mutating func append(_ note: Note) {
        self.notes.append(note)
    }
    
    public init(notes: [MIDITrack.Note] = []) {
        self.notes = notes
    }
    
    /// The range of note value.
    public var noteRange: (min: UInt8, max: UInt8)? {
        guard !self.isEmpty else { return nil }
        let notes = self.notes.map(\.note)
        
        return (notes.min()!, notes.max()!)
    }
    
    public subscript(position: Int) -> Note {
        get {
            self.notes[position]
        }
        set {
            self.notes[position] = newValue
        }
    }
    
    public typealias Index = Int
    
    public typealias Note = MIDITrack.Note
    
    public typealias Element = Note
    
}


extension MIDINotes {
    
    /// A difference score to `rhs` based on the timing of notes.
    ///
    /// The result can be interpreted as the sum of difference in timing. When a key is missing, the penalty is 10 seconds.
    ///
    /// The duration has a weight of 1/10 compared to onset.
    ///
    /// - Returns: The distance in seconds.
    public func distance(to rhs: MIDINotes, missingPenalty: Double = 10) async -> Double {
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
        
        let _lhsGroup = Task {
            var group : [UInt8 : [Matching]] = [:]
            for note in self.notes {
                group[note.note, default: []].append(Matching(note: note, missingPenalty: missingPenalty))
            }
            return group
        }
        
        let _rhsGroup = Task {
            var group : [UInt8 : [Matching]] = [:]
            for note in rhs.notes {
                group[note.note, default: []].append(Matching(note: note, missingPenalty: missingPenalty))
            }
            return group
        }
        
        let lhsGroup = await _lhsGroup.value
        let rhsGroup = await _rhsGroup.value
        
        
        let sums = await (UInt8.min ... UInt8.max).stream.map { note in
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
        
        return try! await sums.sequence.reduce(0, +) // must try! or compiler error
    }
    
}


extension MIDINotes {
    
    /// Separate by note key value
    ///
    /// If `$0 >= key`, then the note goes to `high`
    internal func naiveSeparate(by key: UInt8) -> (low: MIDINotes, high: MIDINotes) {
        var low = MIDINotes()
        var high = MIDINotes()
        
        for note in self.notes {
            if note.note >= key {
                high.append(note)
            } else {
                low.append(note)
            }
        }
        
        return (low, high)
    }
    
    /// Separate the notes by the key value and context
    ///
    /// - Parameters:
    ///   - key: The threshold for naive separate, if `$0 >= key`, then the note goes to `high`. If not specified, one will be automatically determined.
    ///   - clusteringThreshold: The threshold for clustering. The max range of a cluster.
    ///   - tolerance: The tolerance for a note being on the other side given the `key`
    public func separate(
        by key: UInt8? = nil,
        clusteringThreshold: Double,
        tolerance: UInt8
    ) -> (low: MIDINotes, high: MIDINotes) {
        if let key {
            return naiveSeparate(by: key)
        } else {
            let clusters = self.clustered(threshold: clusteringThreshold)
            let ranges = clusters.compactMap(\.noteRange).filter({ $0.max - $0.min > 7 })
            let centers = ranges.map({ (Int($0.max) + Int($0.min))/2 })
            let average = centers.sum / centers.count
            
            let logger = Logger(subsystem: "MIDIKit", category: "MIDINotes.separate")
            let key = UInt8(average)
            logger.info("The separation key is determined to be \(key == 60 ? "Middle C" : "\(key)").")
            
            return naiveSeparate(by: UInt8(average))
        }
    }
    
    
    /// Clustered via hierarchical clustering using a single-linkage method.
    ///
    /// For the purpose of this function, only the onset is considered. Hence a cluster might not be a *chord*.
    internal func clustered(threshold: Double) -> [MIDINotes] {
        guard !self.isEmpty else { return [] }
        
        func calMinDistance(_ lhs: MIDINotes, to rhs: MIDINotes) -> Double? {
            var minDistance: Double?
            
            var i = 0
            while i < lhs.count {
                var j = 0
                while j < rhs.count {
                    let distance = abs(lhs[i].onset - rhs[j].onset)
                    if minDistance == nil || distance < minDistance! {
                        minDistance = distance
                    }
                    
                    j &+= 1
                }
                
                i &+= 1
            }
            
            return minDistance
        }
        
        
        // Step 1: Start by initializing each value as its own cluster
        var clusters = self.map({ MIDINotes(notes: [$0]) })
        
        // Step 2: Perform the clustering process
        var didMerge = true
        
        while didMerge {
            didMerge = false
            var minDistance = Double.greatestFiniteMagnitude
            var mergeIndex1: Int?
            var mergeIndex2: Int?
            
            // Step 3: Find the closest pair of clusters
            var i = 0
            while i < clusters.count {
                var j = i &+ 1
                while j < clusters.count {
                    if let minClusterDistance = calMinDistance(clusters[i], to: clusters[j]),
                       minClusterDistance < minDistance {
                        minDistance = minClusterDistance
                        mergeIndex1 = i
                        mergeIndex2 = j
                    }
                    
                    j &+= 1
                }
                
                i &+= 1
            }
            
            // Step 4: Merge clusters if the minimum distance is within the threshold
            if let index1 = mergeIndex1, let index2 = mergeIndex2, minDistance <= threshold {
                clusters[index1].append(contentsOf: clusters[index2])
                clusters.remove(at: index2)
                didMerge = true
            }
            
//            print("iter")
        }
        
        return clusters
    }
    
    
    /// Returns the list of notes whose lengths are normalized.
    ///
    /// ## Manifesto
    ///
    /// This function serves to normalize the length created by PianoTranscription.
    ///
    /// It seems that PianoTranscription can create excess length due to the sustains.
    ///
    /// These factors can be considered when trying to implement this function.
    ///
    /// - The sustains
    ///   - If offset and inset are in the same sustain region, the length can be arbitrary.
    ///   - If the offset is in a different sustain of inset, the offset must stays in the same sustain region.
    /// - The following notes
    ///   - The PianoTranscription algorithm ensures there are no overlapping notes.
    ///
    /// ---
    ///
    /// After these considerations, it seems we also need a lower bound for the notes. Such lower bound should cease to work when the original note length is lower than such bound. As this function is used to normalize notes lengths, not removing notes.
    ///
    /// Or, we could also round it to the nearest nth note.
    public func normalizedLength() -> MIDINotes {
        fatalError()
    }
    
    /// Normalize by shrinking the length of notes as far as possible, while ensuring the offset are in the same sustain region.
    public func normalizedLengthByShrinkingKeepingOffsetInSameRegion(sustains: MIDISustainEvents) -> MIDINotes {
        let minimumLength = 0.25
        
        return MIDINotes(notes: self.notes.enumerated().map { index, note in
            var note = note
            let onsetSustainRegion = sustains[at: note.onset]
            let offsetSustainRegion = sustains[at: note.offset]
            
            if onsetSustainRegion == offsetSustainRegion || offsetSustainRegion == nil {
                // The length can be free.
                note.duration = minimumLength
                
                // context aware length. Check for next note
                
            } else {
                // the length must span to the found sustain.
                note.offset = offsetSustainRegion!.onset + minimumLength
            }
            
            return note
        })
    }
    
}

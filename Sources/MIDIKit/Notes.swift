//
//  Notes.swift
//  MIDIKit
//
//  Created by Vaida on 8/26/24.
//

import Essentials
import FinderItem
import ConcurrentStream
import OSLog
import DetailedDescription
import Accelerate
import NativeImage


public struct MIDINotes: RandomAccessCollection, Sendable, Equatable, CustomDetailedStringConvertible, ExpressibleByArrayLiteral {
    
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
    
    public mutating func forEach(body: (_ index: Index, _ element: inout Element) -> Void) {
        self.notes.forEach(body: body)
    }
    
    public init(notes: [MIDITrack.Note] = []) {
        self.notes = notes
    }
    
    public init(arrayLiteral elements: Element...) {
        self.notes = elements
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
    
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDINotes>) -> any DescriptionBlockProtocol {
        descriptor.sequence(for: \.notes)
    }
    
    public static let preview: MIDINotes = [
        MIDINote(onset: 1.03, offset: 1.92, note: 54, velocity: 40, channel: 0),
        MIDINote(onset: 1.50, offset: 2.22, note: 61, velocity: 60, channel: 0),
        MIDINote(onset: 1.94, offset: 2.62, note: 54, velocity: 49, channel: 0),
        MIDINote(onset: 2.24, offset: 2.94, note: 61, velocity: 64, channel: 0),
        MIDINote(onset: 2.64, offset: 3.28, note: 54, velocity: 59, channel: 0),
        MIDINote(onset: 2.96, offset: 3.60, note: 61, velocity: 71, channel: 0),
        MIDINote(onset: 3.31, offset: 3.96, note: 54, velocity: 71, channel: 0),
        MIDINote(onset: 3.63, offset: 4.24, note: 61, velocity: 83, channel: 0),
        MIDINote(onset: 3.98, offset: 4.66, note: 54, velocity: 73, channel: 0),
        MIDINote(onset: 4.27, offset: 4.96, note: 61, velocity: 80, channel: 0),
        MIDINote(onset: 4.68, offset: 5.36, note: 54, velocity: 71, channel: 0),
        MIDINote(onset: 4.99, offset: 12.32, note: 61, velocity: 74, channel: 0),
        MIDINote(onset: 5.38, offset: 6.16, note: 54, velocity: 70, channel: 0),
        MIDINote(onset: 5.77, offset: 6.46, note: 62, velocity: 61, channel: 0),
        MIDINote(onset: 6.17, offset: 6.84, note: 54, velocity: 65, channel: 0),
        MIDINote(onset: 6.47, offset: 7.18, note: 62, velocity: 66, channel: 0)
    ]
    
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
    public func clustered(threshold: Double) -> [MIDINotes] {
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
    public func normalizedLengthByShrinkingKeepingOffsetInSameRegion(sustains: MIDISustainEvents, minimumLength: Double = 1/128) -> MIDINotes {
        let notes = self.notes.sorted(by: { $0.onset < $1.onset })
        
        return MIDINotes(notes: notes.enumerated().map { index, note in
            var note = note
            let onsetSustainRegion = sustains[at: note.onset]
            let offsetSustainRegion = sustains[at: note.offset]
            
            if onsetSustainRegion == offsetSustainRegion || offsetSustainRegion == nil {
                // The length can be free.
//                note.duration = minimumLength
                // context aware length. Check for next note
                var next: Element? {
                    var index = index + 1
                    while index < notes.count, notes[index].onset == note.onset {
                        index += 1
                    }
                    return index < notes.count ? notes[index] : nil
                }
                
                if let next {
                    let nextSustain = sustains.first(after: note.offset)
                    
                    let upperBound = Swift.min(next.onset, offsetSustainRegion?.offset ?? nextSustain?.onset ?? Double.greatestFiniteMagnitude, note.offset)
                    let duration = upperBound - note.onset
                    note.duration = Swift.max(minimumLength, duration)
                } else {
                    // is last note. Just ignore
                }
            } else {
                // the length must span to the found sustain.
                note.offset = offsetSustainRegion!.onset + minimumLength
            }
            
            return note
        })
    }
    
    
    /// Identify the gaps in the notes, useful for inferring measures.
    ///
    /// - Parameters:
    ///   - tolerance: Sometimes, notes can overlap while being in different measures. This is the tolerance in beats.
    ///
    /// - Returns: Groups of notes clustered by the gaps.
    ///
    /// - Complexity: O(*n* log *n*), sorting.
    public func identifyGaps(tolerance: Double) -> [MIDINotes] {
        let notes = self.notes.sorted(by: { $0.onset < $1.onset })
        
        var groups: [[Element]] = []
        var currentGroup: [Element] = []
        var currentUpperBound: Double = 0
        
        var i = 0
        while i < notes.count {
            let note = notes[i]
            
            if currentUpperBound != 0 {
                // check if overlap
                if note.onset <= currentUpperBound - tolerance {
                    currentGroup.append(note)
                    currentUpperBound = Swift.max(currentUpperBound, note.offset)
                } else {
                    // open new group
                    groups.append(currentGroup)
                    currentGroup.removeAll(keepingCapacity: true)
                    currentGroup.append(note)
                    currentUpperBound = note.offset
                }
            } else {
                // is first
                currentGroup.append(note)
                currentUpperBound = note.offset
            }
            
            i &+= 1
        }
        
        groups.append(currentGroup)
        
        return groups.map { MIDINotes(notes: $0) }
    }
    
    
    /// Calculates the length of the reference note in beats.
    ///
    /// A reference note is defined as the baseline most commonly occurred note. This could be, for example, 16th note.
    ///
    /// In proper midi, notes should have onsets at *m* \* 1/2^*n*.
    ///
    /// ```swift
    /// // start by normalizing tempo
    /// let referenceNoteLength = container.tracks[0].notes.deriveReferenceNoteLength()
    ///
    /// let tempo = 120 * 1/4 / referenceNoteLength
    /// container.applyTempo(tempo: tempo)
    /// ```
    ///
    /// - Parameters:
    ///   - minimumNoteDistance: Drop notes whose distances from previous notes are less than `minimumNoteDistance`. As these notes could be forming a chord. Defaults to 2^-4, 64th note.
    ///
    /// - Complexity: O(*n* log *n*). Loss function within golden ratio search.
    ///
    /// - Returns: The length of reference note in beats. In 120 bpm, 4/4, which is MIDI default, the new bpm is then 120 \* 0.25 / return value.
    public func deriveReferenceNoteLength(
        minimumNoteDistance: Double = Double(sign: .plus, exponent: -4, significand: 1)
    ) -> Double {
        let distances = [Double](unsafeUninitializedCapacity: self.notes.count - 1) { buffer, initializedCount in
            initializedCount = 0
            
            var i = 1
            while i < self.notes.count {
                let distance = self.notes[i].onset - self.notes[i-1].onset
                if distance >= minimumNoteDistance {
                    buffer[initializedCount] = distance
                    initializedCount &+= 1
                }
                
                i &+= 1
            }
        }
        
        /// - Complexity: O(*n*).
        func loss(distances: [Double], reference: Double) -> Double {
            var i = 1
            var loss: Double = 0
            while i < distances.count {
                let remainder = distances[i].truncatingRemainder(dividingBy: reference)
                assert(remainder >= 0)
                loss += Swift.min(remainder, Swift.max(reference - remainder, 0))
                
                i &+= 1
            }
            
            return loss
        }
        
        /// - Complexity: O(*n* log *n*).
        func goldenSectionSearch(left: Double, right: Double, tolerance: Double = 1e-5, body: (Double) -> Double) -> Double {
            let gr = (sqrt(5) + 1) / 2 // Golden ratio constant
            
            var a = left
            var b = right
            
            // We are looking for the minimum, so we apply the golden section search logic
            var c = b - (b - a) / gr
            var d = a + (b - a) / gr
            
            while abs(c - d) > tolerance {
                if body(c) < body(d) {
                    b = d
                } else {
                    a = c
                }
                
                c = b - (b - a) / gr
                d = a + (b - a) / gr
            }
            
            // The point of minimum loss is between a and b
            return (b + a) / 2
        }
        
        return goldenSectionSearch(left: 0, right: vDSP.mean(distances) * 3 / 2) {
            loss(distances: distances, reference: $0)
        }
    }
    
    #if os(macOS)
    /// **DEBUG USE** Draw a histogram of the notes distances from direct previous notes.
    @MainActor public func drawDistanceDistribution(
        minimumNoteDistance: Double = Double(sign: .plus, exponent: -4, significand: 1)
    ) {
        let distances = [Double](unsafeUninitializedCapacity: self.notes.count - 1) { buffer, initializedCount in
            initializedCount = 0
            
            var i = 1
            while i < self.notes.count {
                let distance = self.notes[i].onset - self.notes[i-1].onset
                if distance >= minimumNoteDistance {
                    buffer[initializedCount] = distance
                    initializedCount &+= 1
                }
                
                i &+= 1
            }
        }
        
        DistributionView(values: distances)
            .frame(width: 800, height: 400)
            .render(to: FinderItem.desktopDirectory.appending(path: "frequency.pdf"))
    }
    #endif
    
}

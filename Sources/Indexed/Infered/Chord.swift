//
//  Chord.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Foundation
import DetailedDescription
import Accelerate
import Essentials
import Optimization


/// chords are keys that needs to be pressed at the same time.
///
/// `chord`s serve primarily for normalization, arpeggios are not considered in the same chord.
///
/// `cluster` and `chord` can be used interchangeably.
///
/// > Warning:
/// > The `Chord`s hold non-owning references to `IndexedContainer.contents`.
/// >
/// > You can use `extendLifetime(_:)` to ensure a container is not deallocated until it returns.
/// > ```swift
/// > extendLifetime(container)
/// > ```
public struct Chord: RandomAccessCollection, Hashable {
    
    /// contents are always sorted by their onsets.
    ///
    /// contents are disjoint.
    var contents: [ReferenceNote]
    
    /// The max offset in beats. This is determined by the onset of next consecutive note.
    var maxOffset: Double?
    
    public var features: Features
    
    
    public var startIndex: Int { 0 }
    public var endIndex: Int { contents.count }
    
    /// The onset of the earliest note.
    public var leadingOnset: Double {
        self.contents.first!.onset
    }
    
    public var trailingOffset: Double {
        self.contents.max(of: \.offset)!
    }
    
    /// The max offset `-` min onset.
    public var duration: Double {
        trailingOffset - self.leadingOnset
    }
    
    public var pitchSpan: UInt8 {
        self.contents.max(of: \.note)! - self.contents.min(of: \.note)!
    }
    
    
    public init(contents: [ReferenceNote], maxOffset: Double?, features: Features = []) {
        self.contents = contents
        self.maxOffset = maxOffset
        self.features = features
    }
    
    public subscript(position: Int) -> Element {
        get { self.contents[position] }
        set { self.contents[position] = newValue }
    }
    
    public typealias Element = ReferenceNote
    
    /// - precondition: `other` must be `self`'s predecessor
    ///
    /// - Complexity: O(other)
    private mutating func prepend(contentsOf other: Chord) {
        self.contents = self.contents + other.contents
        
        self.maxOffset = if self.maxOffset != nil && other.maxOffset != nil {
            Swift.min(self.maxOffset!, other.maxOffset!)
        } else if self.maxOffset != nil {
            self.maxOffset
        } else if other.maxOffset != nil {
            other.maxOffset
        } else {
            nil
        }
    }
    
    /// Groups the notes of `container` into chords: keys that are pressed together.
    ///
    /// Each returned chord is guaranteed to be non-empty, holds no key twice, and is sorted by onset. Chords are sorted by `leadingOnset`. A note that is part of a glissando is a chord of its own, with the ``Features/glissando`` feature.
    ///
    /// By default, the library judges every two notes that are next to each other in time, and decides whether they were struck together from the gap between them, how the two keys relate (a run goes by steps, a doubling by octaves), how crowded the neighborhood is, and whether the pair stands apart from the notes around it. Notes played slightly apart are told from a fast sequence by that context, which a single window cannot do.
    ///
    /// If the algorithm that transcribed `container` is known, passing it lets the library also use what that algorithm is known to get right, for example how its timing is quantized, when it releases a note, or how loud it reports a note. It also tells what to leave out: ``TranscriptionAlgorithm/pianoTranscription`` reports offsets that cannot be relied on, so they are not looked at.
    ///
    /// Pass `Spec(duration:)` to opt out and use a constant window instead: consecutive notes whose onsets are at most `duration` apart are in the same chord. `Spec(duration: 0.1)` is what the library did by default before it judged pairs.
    ///
    /// - Parameters:
    ///   - container: The notes to group.
    ///   - spec: `Spec()` lets the library judge the pairs. `Spec(duration:)` selects the constant window.
    ///   - transcriptionAlgorithm: The algorithm that transcribed `container`, or `nil` when it is not known. It has no effect when `spec` is `Spec(duration:)`: the explicit window wins.
    ///
    /// - Complexity: O(n log n) for the default. For a constant window, O(n^2) worse case, O(n log n) practically.
    public static func makeChords(
        from container: IndexedContainer,
        spec: Spec = Spec(),
        optimizeFor transcriptionAlgorithm: TranscriptionAlgorithm? = nil
    ) -> [Chord] {
        if let duration = spec.explicitDuration {
            return makeConstantWindowChords(from: container, duration: duration)
        }

        return Arbiter(optimizingFor: transcriptionAlgorithm).makeChords(from: container)
    }
    
    
    /// The constant-window algorithm: consecutive notes whose onsets are at most `duration` apart are in the same chord, unless that would put one key in a chord twice, or the notes are part of a glissando.
    ///
    /// - Complexity: O(n^2) worse case, O(n log n) practically.
    private static func makeConstantWindowChords(
        from container: IndexedContainer,
        duration: Double
    ) -> [Chord] {
        guard !container.isEmpty else { return [] }
        
        /// Returns minimum distance between onsets of any two notes in each cluster.
        ///
        /// - precondition: `lhs` \< `rhs`
        ///
        /// - Complexity: O(1)
        @inline(__always)
        func minDistance(_ lhs: Chord, _ rhs: Chord) -> Double {
            rhs.first!.onset - lhs.last!.onset
        }
        
        /// - Complexity: O(n)
        func clustersCanMerge(_ lhs: Chord, _ rhs: Chord) -> Bool {
            guard !lhs.features.contains(.glissando) && !rhs.features.contains(.glissando) else { return false }
            
            // no duplicated notes, ensured by the max offset
            guard lhs.maxOffset.isNil(or: { rhs.contents.last!.onset < $0 }) else { return false }
            
            // ensure minimum distance is smaller than threshold: O(1)
            guard minDistance(lhs, rhs) <= duration else { return false }
            
            return true
        }
        
        
        // Initializing each value as its own cluster
        // - Complexity: O(n log(n)), sorting
        var clusters: [Chord] = []
        clusters.reserveCapacity(container.count)
        for i in 21...108 {
            guard let notes = container.notes[UInt8(i)] else { continue }
            var iterator = notes.makeIterator()
            var current = iterator.next()
            var next = iterator.next()
            while current != nil {
                clusters.append(Chord(contents: [current!], maxOffset: next?.onset))
                current = next
                next = iterator.next()
            }
        }
        clusters.sort(by: { $0.first!.onset < $1.first!.onset })
        
        // extract features
        for run in glissandoRuns(in: clusters.map { $0.first! }, sustains: container.sustains) {
            for index in run {
                clusters[index].features.insert(.glissando)
            }
        }
        
        // chords are disjoint
        // initial merge: O(n)
        let queue = InlineDeque(consume clusters) // the queue holds the source of truth, while `merged` refers to `queue` for chords.
        let merged = RingBuffer<InlineDeque<Chord>.Index>(minimumCapacity: queue.count)
        var front = queue.firstIndex
        while let node = front {
            merged.append(node)
            front = queue.index(after: node)
        }
        
        // merges
        var removedIndices: Set<InlineDeque<Chord>.Index> = []
        while let cluster = merged.removeFirst() {
            guard !removedIndices.contains(cluster) else { continue }
            let lhs = queue.index(before: cluster)
            let rhs = queue.index(after: cluster)

            let lhsCanMerge = lhs.map { clustersCanMerge(queue[$0], queue[cluster]) } ?? false
            let rhsCanMerge = rhs.map { clustersCanMerge(queue[cluster], queue[$0]) } ?? false

            if rhsCanMerge && (lhsCanMerge => minDistance(queue[lhs!], queue[cluster]) > minDistance(queue[cluster], queue[rhs!])) {
                queue.update(at: cluster) { $0.prepend(contentsOf: queue[rhs!]) }
                merged.append(cluster)
                removedIndices.insert(rhs!)
                queue.remove(at: rhs!)
            }
            // Can ever only merge right, if left merge is better, simply don't, and wait for next right merge
            // otherwise the merged left is still in the `merged` queue, waiting to be merged (again)
        }
        
        return Array(consume queue)
    }
    
    
    /// The runs of notes that are a glissando: 11 or more consecutive notes that all move in one direction, each shorter than 0.2 beat and at most 0.2 beat after the one before.
    ///
    /// A run only counts when the first note starts and ends within the same sustain state. Every run is returned once; a note that follows a run directly is not tried as the start of the next, which is how the detection has always behaved.
    ///
    /// - Parameter notes: Single notes, sorted by onset.
    ///
    /// - Complexity: O(n)
    static func glissandoRuns(in notes: [ReferenceNote], sustains: MIDISustainEvents) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        let order: [(UInt8, UInt8) -> Bool] = [{ $0 <= $1 }, {$0 >= $1}]
        
        for order in order {
            var index = 0
            while index < notes.count {
                defer { index &+= 1 }
                let first = notes[index]
                guard sustains[at: first.onset] == sustains[at: first.offset] else { continue } // within the sustain
                guard index + 1 < notes.count else { break }
                
                var previous = first
                var next = index + 1
                while next < notes.count {
                    let candidate = notes[next]
                    guard candidate.offset < candidate.onset + 0.2,
                          order(candidate.note, previous.note),
                          candidate.onset - previous.onset <= 0.2
                    else { break }
                    previous = candidate
                    next += 1
                }
                guard next - index > 10 else { continue }
                
                runs.append(index ..< Swift.min(next, notes.count))
                index = next
            }
        }
        
        return runs
    }
    

    /// Chords are split making sure that notes within the same chord should be played by the same hand, while notes in different chord could be played by the same hand.
    public static func makeSingleHandedChords(
        from container: IndexedContainer,
        spec: Spec = Spec(),
        optimizeFor transcriptionAlgorithm: TranscriptionAlgorithm? = nil
    ) -> [Chord] {
        var chords = Chord.makeChords(from: container, spec: spec, optimizeFor: transcriptionAlgorithm)
        let reachLimit: UInt8 = 9
        let octaveTolerance = 1
        let gapWeight = 1.5
        let spanWeight = 0.2
        
        for (index, chord) in chords.enumerated() {
            let span = chord.pitchSpan
            guard span > 12 else { continue }
            guard chord.count > 2 || span > 14 else { continue }
            
            let notes = chord.contents.sorted(on: \.note, by: <)
            guard notes.count >= 2 else { continue }
            
            let totalSpan = Int(notes.last!.note) - Int(notes.first!.note)
            var bestSplit: Int?
            var bestCost = Double.infinity
            
            for split in 1..<notes.count {
                let leftSpan = Int(notes[split - 1].note) - Int(notes.first!.note)
                let rightSpan = Int(notes.last!.note) - Int(notes[split].note)
                let maxSpan = Swift.max(leftSpan, rightSpan)
                let gap = Int(notes[split].note) - Int(notes[split - 1].note)
                let remainder = gap % 12
                let octaveCloseness = Swift.min(remainder, 12 - remainder)
                let octavePenalty = octaveCloseness <= octaveTolerance
                ? Double(octaveTolerance - octaveCloseness + 1) * 6.0
                : 0.0
                let reachPenalty = Swift.max(0, maxSpan - Int(reachLimit))
                let imbalance = abs(leftSpan - rightSpan)
                
                let cost = Double(maxSpan)
                + Double(reachPenalty)
                + Double(imbalance) * spanWeight
                - Double(gap) * gapWeight
                + octavePenalty
                
                if cost < bestCost {
                    bestCost = cost
                    bestSplit = split
                }
            }
            
            guard let splitIndex = bestSplit else { continue }
            guard bestCost + 0.5 < Double(totalSpan) else { continue }
            
            let leftSlice = Array(notes[..<splitIndex])
            let rightSlice = Array(notes[splitIndex...])
            guard !leftSlice.isEmpty, !rightSlice.isEmpty else { continue }
            
            let leftNotes = leftSlice.sorted(on: \.onset, by: <)
            let rightNotes = rightSlice.sorted(on: \.onset, by: <)
            
            chords[index].contents = leftNotes
            chords[index].maxOffset = chord.maxOffset
            chords[index].features = chord.features
            chords[index].features.insert(.preferLeftHand)
            
            var rightFeatures = chord.features
            rightFeatures.insert(.preferRightHand)
            let rightChord = Chord(
                contents: rightNotes,
                maxOffset: chord.maxOffset,
                features: rightFeatures
            )
            chords.append(rightChord)
        }
        
        return chords.sorted(on: \.leadingOnset, by: <)
    }
    
    
    /// Selects the algorithm that forms the chords, and for the constant window, its window.
    ///
    /// Durations are in beats, in 120BPM.
    public struct Spec: Sendable, Hashable {
        
        /// The window of the constant-window algorithm, or `nil` when the library chooses the algorithm.
        let explicitDuration: Double?
        
        /// The maximum distance apart of the least apart elements to be considered in the same chord.
        ///
        /// This effectively is the min duration of a note. It is 0.1 beat (50 ms) unless set on creation.
        var duration: Double {
            explicitDuration ?? Spec.defaultDuration
        }
        
        static let defaultDuration = 0.1
        
        
        /// Lets ``Chord/makeChords(from:spec:optimizeFor:)`` choose the algorithm.
        public init() {
            self.explicitDuration = nil
        }
        
        /// A constant window: notes are in the same chord when consecutive onsets are at most `duration` beats apart.
        ///
        /// ``Chord/makeChords(from:spec:optimizeFor:)`` then ignores its `optimizeFor` argument. `Spec(duration: 0.1)` is what `Spec()` was before the library chose the algorithm.
        public init(duration: Double) {
            self.explicitDuration = duration
        }
        
    }
    
    
    public struct Features: OptionSet, Sendable, Hashable {
        
        public let rawValue: UInt8
        
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        
        public static let glissando = Features(rawValue: 1 << 0)
        public static let preferLeftHand = Features(rawValue: 1 << 1)
        public static let preferRightHand = Features(rawValue: 1 << 2)
        
    }
    
}


extension Chord: DetailedStringConvertible {
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<Chord>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.contents)
            descriptor.optional(for: \.maxOffset)
        }
    }
    
}


extension Chord: CustomStringConvertible {
    
    
    public var description: String {
        "[" + self.contents.map(\.pointee.description).joined(separator: ", ") + "]"
    }
    
}


extension Array<Chord> {
    
    /// Returns the first interval whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func firstIndex(after timeStamp: Double) -> Index? {
        var left = 0
        var right = self.count
        
        while left < right {
            let mid = (left + right) / 2
            if self[mid].leadingOnset > timeStamp {
                right = mid
            } else {
                left = mid + 1
            }
        }
        
        // After the loop, 'left' is the index of the first element greater than the value, if it exists.
        // Check if 'left' is within bounds and return the element if it exists.
        if left < self.count {
            return left
        } else {
            return nil
        }
    }
    
}


extension IndexedContainer {
    
    /// - Parameter transcriptionAlgorithm: The algorithm that transcribed the container, when it is known. See ``Chord/makeChords(from:spec:optimizeFor:)``.
    public borrowing func chords(optimizeFor transcriptionAlgorithm: TranscriptionAlgorithm? = nil) -> [Chord] {
        Chord.makeChords(from: self, optimizeFor: transcriptionAlgorithm)
    }
    
}

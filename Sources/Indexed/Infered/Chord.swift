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
public struct Chord: RandomAccessCollection {
    
    /// contents are always sorted by their onsets.
    ///
    /// contents are disjoint.
    var contents: [ReferenceNote]
    
    /// The max offset in beats. This is determined by the onset of next consecutive note.
    var maxOffset: Double?
    
    public var startIndex: Int { 0 }
    public var endIndex: Int { contents.count }
    
    var leadingOnset: Double {
        self.contents.first!.onset
    }
    
    var pitchSpan: UInt8 {
        self.contents.max(of: \.note)! - self.contents.min(of: \.note)!
    }
    
    
    public init(contents: [ReferenceNote], maxOffset: Double?) {
        self.contents = contents
        self.maxOffset = maxOffset
    }
    
    public subscript(position: Int) -> Element {
        self.contents[position]
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
    
    /// Each returned chord is guaranteed to be non-empty.
    ///
    /// - Complexity: O(n^2) worse case, O(n log n) practically.
    public static func makeChords(
        from container: IndexedContainer,
        spec: Spec = Spec()
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
            // no duplicated notes, ensured by the max offset
            guard lhs.maxOffset.isNil(or: { rhs.contents.last!.onset < $0 }) else { return false }
            
            // ensure minimum distance is smaller than threshold: O(1)
            guard minDistance(lhs, rhs) <= spec.duration else { return false }
            
            return true
        }
        
        
        // Step 1: Start by initializing each value as its own cluster
        // - Complexity: O(n log(n)), sorting
        var clusters: [Chord] = []
        clusters.reserveCapacity(container.count)
        for i in 21...108 {
            guard var notes = container.notes[UInt8(i)]?.makeIterator() else { continue }
            var current = notes.next()
            var next = notes.next()
            while current != nil {
                clusters.append(Chord(contents: [current!], maxOffset: next?.onset))
                current = next
                next = notes.next()
            }
        }
        clusters.sort(by: { $0.first!.onset < $1.first!.onset })
        
        // Step 2: Perform the clustering process
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
        while let cluster = merged.removeFirst() {
            let lhs = queue.index(before: cluster)
            let rhs = queue.index(after: cluster)
            
            let lhsCanMerge = lhs.map { clustersCanMerge(queue[$0], queue[cluster]) } ?? false
            let rhsCanMerge = rhs.map { clustersCanMerge(queue[cluster], queue[$0]) } ?? false
            
            if rhsCanMerge && (lhsCanMerge => minDistance(queue[lhs!], queue[cluster]) > minDistance(queue[cluster], queue[rhs!])) {
                queue.update(at: cluster) { $0.prepend(contentsOf: queue[rhs!]) }
                merged.append(cluster)
                queue.remove(at: rhs!)
            }
            // Can ever only merge right, if left merge is better, simply don't, and wait for next right merge
            // otherwise the merged left is still in the `merged` queue, waiting to be merged (again)
        }
        
        
        return Array(consume queue)
    }
    
    
    /// Chords are split making sure that notes within the same chord should be played by the same hand, while notes in different chord could be played by the same hand.
    public static func makeSingleHandedChords(
        from container: IndexedContainer,
        spec: Spec = Spec()
    ) -> [Chord] {
        var chords = self.makeChords(from: container, spec: spec)
        
        for (index, chord) in chords.enumerated() {
            let span = chord.pitchSpan
            guard span > 12 else { continue }
            guard chord.count > 2 || span > 18 else { continue }
            
            let notes = chord.contents.sorted(on: \.note, by: <)
            
            // cluster into hands: O(n)
            var left: [ReferenceNote] = []
            var right: [ReferenceNote] = []
            left.reserveCapacity(notes.count)
            right.reserveCapacity(notes.count)

            let minIndex = notes.minIndex(of: \.note)
            let maxIndex = notes.maxIndex(of: \.note)
            let min = notes[minIndex!]
            let max = notes[maxIndex!]

            notes.forEach { index, element in
                if index == minIndex {
                    left.append(min)
                } else if index == maxIndex {
                    right.append(max)
                } else {
                    let leftDistance = element.note - min.note
                    let rightDistance = max.note - element.note
                    if leftDistance < rightDistance {
                        left.append(element)
                    } else {
                        right.append(element)
                    }
                }
            }
            
            chords[index].contents = left.sorted()
            chords.append(Chord(contents: right.sorted(), maxOffset: nil))
        }
        
        return chords.sorted(on: \.leadingOnset, by: <)
    }
    
    
    /// Spec durations are in beats, in 120BPM.
    public struct Spec {
        
        /// The maximum distance apart of the least apart elements to be considered in the same chord.
        ///
        /// The effectively is the min duration of a note.
        let duration: Double = 0.1
        
//        /// Width of a single hand, defaults to 15, which is octave plus two white keys
//        let handWidth: UInt8 = 13 + 3
        
        public init() { }
        
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
        self.contents.description
    }
    
}


extension Array<Chord> {
    
    /// Returns the first interval whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    func firstIndex(after timeStamp: Double) -> Index? {
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

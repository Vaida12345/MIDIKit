//
//  Chord.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Foundation
import DetailedDescription
import Accelerate


/// chords are keys that needs to be pressed at the same time.
///
/// Currently it represents notes that *two hands* can play simultaneously. The algorithm for obtain chord for individual hand exists in a previous commit.
public final class Chord: RandomAccessCollection {
    
    var contents: [ReferenceNote]
    
    /// The max offset in beats. This is determined by the onset of next consecutive note.
    var maxOffset: Double?
    
    public var startIndex: Int { 0 }
    public var endIndex: Int { contents.count }
    
    
    public init(contents: [ReferenceNote], maxOffset: Double?) {
        self.contents = contents
        self.maxOffset = maxOffset
    }
    
    public subscript(position: Int) -> Element {
        self.contents[position]
    }
    
    public typealias Element = ReferenceNote
    
    private func append(contentsOf other: Chord) {
        self.contents = (self.contents + other.contents).sorted(by: { $0.onset < $1.onset })
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
    
    public static func makeChords(
        from container: IndexedContainer,
        spec: Spec = Spec()
    ) async -> [Chord] {
        guard !container.combinedNotes.isEmpty else { return [] }
        let threshold = spec.duration
        
        func calMinDistance(_ lhs: Chord, to rhs: Chord) -> Double? {
            var minDistance: Double?
            var minNoteDistance: Int?
            
            var i = 0
            while i < lhs.endIndex {
                var j = 0
                while j < rhs.endIndex {
                    let distance = abs(lhs[i].onset - rhs[j].onset)
                    if minDistance == nil || distance < minDistance! {
                        minDistance = distance
                    }
                    var noteDistance = abs(Int(lhs[i].note) - Int(rhs[j].note))
                    if noteDistance == 12 {
                        noteDistance = 0 // special case
                    }
                    if minNoteDistance == nil || noteDistance < minNoteDistance! {
                        minNoteDistance = noteDistance
                    }
                    
                    j &+= 1
                }
                
                i &+= 1
            }
            
            let lhsAverage = lhs.contents.average(of: \.duration)!
            let rhsAverage = rhs.contents.average(of: \.duration)!
            let diff = abs(lhsAverage - rhsAverage)
            let normalizedDiff = diff / Swift.max(lhsAverage, rhsAverage)
            
            let features: [Double] = [minDistance! / threshold, Double(minNoteDistance!) / Double(spec.keysSpan), normalizedDiff]
            return sqrt(vDSP.dot(features, features))
        }
        
        func clustersCanMerge(_ lhs: Chord, _ rhs: Chord) -> Bool {
            guard lhs.contents.count &+ rhs.contents.count < spec.maxNoteCount else { return false }
            guard Swift.max(lhs.max(of: \.note)!, rhs.max(of: \.note)!) - Swift.min(lhs.min(of: \.note)!, rhs.min(of: \.note)!) < spec.keysSpan else { return false }
            let maxOnset = Swift.max(lhs.contents.last!.onset, rhs.contents.last!.onset)
            guard lhs.maxOffset.isNil(or: { maxOnset < $0 }) && rhs.maxOffset.isNil(or: { maxOnset < $0 }) else { return false }
            
            return true
        }
        
        
        // Step 1: Start by initializing each value as its own cluster
        nonisolated(unsafe)
        var clusters: [Chord] = []
        for i in 21...108 {
            var notes = container.notes[UInt8(i)]?.makeIterator()
            var current = notes?.next()
            var next = notes?.next()
            while current != nil {
                clusters.append(Chord(contents: [current!], maxOffset: next?.onset))
                current = next
                next = notes?.next()
            }
        }
        clusters.sort(by: { $0.first!.onset < $1.first!.onset })
        
        // Step 2: Perform the clustering process
        var didMerge = true
        let root3 = sqrt(3)
        while didMerge {
            didMerge = false
            var minDistance = Double.greatestFiniteMagnitude
            var mergeIndex1: Int?
            var mergeIndex2: Int?
            
            // Step 3: Find the closest pair of clusters
            var i = 0
            while i < clusters.endIndex {
                var j = i &+ 1
                while j < clusters.endIndex && j < i + spec.clusterMaxDistance {
                    if clustersCanMerge(clusters[i], clusters[j]),
                       let minClusterDistance = calMinDistance(clusters[i], to: clusters[j]),
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
            if let index1 = mergeIndex1, let index2 = mergeIndex2, minDistance < root3 {
                clusters[index1].append(contentsOf: clusters[index2])
                clusters.remove(at: index2)
                didMerge = true
            }
        }
        
        return clusters.sorted(on: { $0.first!.onset }, by: <)
    }
    
    public struct Spec {
        
        let duration: Double = 1/8
        
        /// Assuming the mergable clusters are near each other, this is the length of pairs checked.
        let contextLength: Int = 15
        
        /// Max distance to look ahead for another note in one cluster.
        let clusterMaxDistance: Int = 8
        
        /// Max number of notes in one chord.
        ///
        /// 5 finders per hand, 5 notes.
        let maxNoteCount = 5
        
        /// The max span of a hand, 7+2 white notes should be enough
        let keysSpan = 12 + 3
        
        public init() { }
        
    }
    
}


extension Chord: CustomDetailedStringConvertible {
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<Chord>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.contents)
            descriptor.optional(for: \.maxOffset)
        }
    }
    
}


extension Optional {
    
    func isNil(or predicate: (Wrapped) -> Bool) -> Bool {
        switch self {
        case .none:
            return true
        case .some(let wrapped):
            return predicate(wrapped)
        }
    }
    
}


extension RandomAccessCollection where Index == Int {
    
    /// The max `member` of this collection.
    ///
    /// This is equivalent to
    /// ```swift
    /// self.map(member).max()
    /// ```
    /// But more efficient.
    @inlinable
    public func average<T, E>(of member: (Element) throws(E) -> T) throws(E) -> T? where E: Error, T: BinaryFloatingPoint {
        var i = self.startIndex
        var cumulative: T = 0
        while i < self.endIndex {
            let current = try member(self[i])
            cumulative += current
            i &+= 1
        }
        return cumulative / T(self.count)
    }
    
}

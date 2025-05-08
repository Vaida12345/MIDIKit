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


/// chords are keys that needs to be pressed at the same time.
///
/// Currently it represents notes that *two hands* can play *simultaneously*. `chord`s serve primarily for normalization, arpeggios are not considered in the same chord.
///
/// `cluster` and `chord` can be used interchangeably.
///
/// The algorithm for obtain chord for individual hand exists in a previous commit.
public final class Chord: RandomAccessCollection {
    
    /// contents are always sorted by their onsets
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
    
    /// - Complexity: O(n)
    private func append(contentsOf other: Chord) {
        let lhs = self.contents // copy
        self.contents.removeAll(keepingCapacity: true)
        self.contents.reserveCapacity(self.contents.count + other.contents.count)
        
        var i = 0, j = 0
        while i < lhs.count, j < other.count {
            if lhs[i].onset < other[j].onset {
                self.contents.append(lhs[i])
                i &+= 1
            } else {
                self.contents.append(other[j])
                j &+= 1
            }
        }
        
        if i < lhs.count {
            self.contents.append(contentsOf: lhs[i...])
        }
        if j < other.count {
            self.contents.append(contentsOf: other[j...])
        }
        
        
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
    public static func makeChords(
        from container: IndexedContainer,
        spec: Spec = Spec()
    ) async -> [Chord] {
        guard !container.combinedNotes.isEmpty else { return [] }
        
        /// Returns minimum distance between onsets of any two notes in each cluster.
        ///
        /// - Complexity: O(n)
        func calMinDistance(_ lhs: Chord, to rhs: Chord) -> Double? {
            // merge
            var merged: [ReferenceNote] = []
            merged.reserveCapacity(lhs.count + rhs.count)
            
            var i = 0, j = 0
            while i < lhs.count, j < rhs.count {
                if lhs[i].onset < rhs[j].onset {
                    merged.append(lhs[i])
                    i &+= 1
                } else {
                    merged.append(rhs[j])
                    j &+= 1
                }
            }
            
            if i < lhs.count {
                merged.append(contentsOf: lhs[i...])
            }
            if j < rhs.count {
                merged.append(contentsOf: rhs[j...])
            }
            
            
            var minDistance: Double?
            
            i = 0
            let end = lhs.endIndex - 1
            while i < end {
                let distance = merged[i + 1].onset - merged[i].onset
                if minDistance == nil || distance < minDistance! {
                    minDistance = distance
                }
                
                i &+= 1
            }
            
            return minDistance!
        }
        
        /// - Complexity: O(n)
        func clustersCanMerge(_ lhs: Chord, _ rhs: Chord) -> Bool {
            let maxOnset = Swift.max(lhs.contents.last!.onset, rhs.contents.last!.onset)
            // no duplicated notes, ensured by the max offset
            guard lhs.maxOffset.isNil(or: { maxOnset < $0 }) && rhs.maxOffset.isNil(or: { maxOnset < $0 }) else { return false }
            
            // Ensure the widths is smaller than threshold O(1)
            guard Swift.max(lhs.last!.onset, rhs.last!.onset) - Swift.min(lhs.first!.onset, rhs.first!.onset) < spec.clusterWidth else { return false }
            
            
            // hand-based analysis
            guard (lhs.count + rhs.count) > 2 else { return true }
            let contents = lhs.contents + rhs.contents
            
            // cluster into hands O(n)
            var left: [ReferenceNote] = []
            var right: [ReferenceNote] = []
            
            let minIndex = contents.minIndex(of: \.note)
            let maxIndex = contents.minIndex(of: \.note)
            let min = contents[minIndex!]
            let max = contents[maxIndex!]
            
            contents.forEach { index, element in
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
            
            // ensure hands can reach O(n)
            guard left.max(of: \.note)! - left.min(of: \.note)! < spec.handWidth,
                    right.max(of: \.note)! - right.min(of: \.note)! < spec.handWidth else { return false }
            
            
            return true
        }
        
        
        // Step 1: Start by initializing each value as its own cluster
        // - Complexity: O(n log(n)), sorting
        var clusters: [Chord] = []
        clusters.reserveCapacity(container.combinedNotes.count)
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
        var startIndex = 0
        while startIndex < clusters.endIndex {
            var minDistance = Double.greatestFiniteMagnitude
            var mergeIndex1: Int?
            var mergeIndex2: Int?
            
            // Step 3: Find the closest pair of clusters
            var i = startIndex
            while i < Swift.min(clusters.endIndex, startIndex + spec.contextLength) {
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
            if let index1 = mergeIndex1, let index2 = mergeIndex2, minDistance <= spec.duration {
                clusters[index1].append(contentsOf: clusters[index2])
                clusters.remove(at: index2)
            } else {
                startIndex &+= 1
            }
        }
        
        return clusters.sorted(on: { $0.first!.onset }, by: <)
    }
    
    /// Spec durations are in beats, in 120BPM.
    public struct Spec {
        
        /// The maximum distance apart of any two elements to be considered within the same chord.
        let duration: Double = 0.1
        
        /// The max duration of one single cluster.
        let clusterWidth: Double = 0.2
        
        /// Assuming the mergable clusters are near each other, this is the length of pairs checked.
        let contextLength: Int = 15
        
        /// Max distance to look ahead for another note in one cluster.
        let clusterMaxDistance: Int = 8
        
        /// Width of a single hand, defaults to 15, which is octave plus two white keys
        let handWidth: UInt8 = 15
        
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

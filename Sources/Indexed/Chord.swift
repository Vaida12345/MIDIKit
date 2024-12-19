//
//  Chord.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Foundation
import DetailedDescription


/// chords are keys that needs to be pressed at the same time.
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
    
    private var maxNote: UInt8? {
        var i = 0
        var max: UInt8? = nil
        while i < self.contents.count {
            if max == nil || self.contents[i].note > max! {
                max = self.contents[i].note
            }
            i &+= 1
        }
        return max
    }
    private var minNote: UInt8? {
        var i = 0
        var min: UInt8? = nil
        while i < self.contents.count {
            if min == nil || self.contents[i].note < min! {
                min = self.contents[i].note
            }
            i &+= 1
        }
        return min
    }
    
    
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
    ) -> [Chord] {
        guard !container.combinedNotes.isEmpty else { return [] }
        let threshold = spec.duration
        
        func calMinDistance(_ lhs: Chord, to rhs: Chord) -> Double? {
            var minDistance: Double?
            var minNoteDistance: Int?
            
            var i = 0
            while i < lhs.count {
                var j = 0
                while j < rhs.count {
                    let distance = abs(lhs[i].onset - rhs[j].onset)
                    if minDistance == nil || distance < minDistance! {
                        minDistance = distance
                    }
                    let noteDistane = abs(Int(lhs[i].note) - Int(rhs[j].note))
                    if minNoteDistance == nil || noteDistane < minNoteDistance! {
                        minNoteDistance = noteDistane
                    }
                    
                    j &+= 1
                }
                
                i &+= 1
            }
            
            return sqrt(pow(minDistance! / threshold, 2) + pow(Double(minNoteDistance!) / Double(spec.keysSpan), 2))
        }
        
        func clustersCanMerge(_ lhs: Chord, _ rhs: Chord) -> Bool {
            guard lhs.count + rhs.count < spec.maxCount else { return false }
            guard Swift.max(lhs.maxNote!, rhs.maxNote!) - Swift.max(lhs.minNote!, rhs.minNote!) < spec.keysSpan else { return false }
            let maxOnset = Swift.max(lhs.contents.last!.onset, rhs.contents.last!.onset)
            guard lhs.maxOffset.isNil(or: { maxOnset < $0 }) && rhs.maxOffset.isNil(or: { maxOnset < $0 }) else { return false }
            
            return true
        }
        
        
        // Step 1: Start by initializing each value as its own cluster
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
        while didMerge {
            didMerge = false
            var minDistance = Double.greatestFiniteMagnitude
            var mergeIndex1: Int?
            var mergeIndex2: Int?
            
            // Step 3: Find the closest pair of clusters
            var i = 0
            while i < clusters.count {
                var j = i &+ 1
                while j < clusters.count && j < i + spec.maxCount {
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
            if let index1 = mergeIndex1, let index2 = mergeIndex2, minDistance <= 1 {
                clusters[index1].append(contentsOf: clusters[index2])
                clusters.remove(at: index2)
                didMerge = true
            }
        }
        
        return clusters.sorted(on: { $0.first!.onset }, by: <)
    }
    
    public struct Spec {
        
        let keysSpan = 12 + 3
        
        let duration: Double = 1/8
        
        let maxCount = 5
        
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

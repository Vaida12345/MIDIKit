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
/// Currently it represents notes that *two hands* can play simultaneously. The algorithm for obtain chord for individual hand exists in a previous commit.
public final class Chord: RandomAccessCollection {
    
    var contents: [ReferenceNote]
    
    /// The max offset in beats. This is determined by the onset of next consecutive note.
    var maxOffset: Double?
    
    var preferredHand: Hand?
    
    public var hand: Hand?
    
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
    
    /// Each returned chord is guaranteed to be non-empty.
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
                        // sometimes, notes with 7 notes apart should be played together, check for this special case.
                        let notes = container.combinedNotes.range(Swift.min(lhs[i].onset, rhs[j].onset) ... Swift.max(lhs[i].onset, rhs[j].onset))
                        
                        if Swift.min(lhs[i].note, rhs[j].note) == notes.min(of: \.note) || Swift.max(lhs[i].note, rhs[j].note) == notes.max(of: \.note) {
                            noteDistance = 0 // special case
                        }
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
        
        let chords = clusters.sorted(on: { $0.first!.onset }, by: <)
        chords.forEach { _, chord in
            let mapped = chord.map { chord in
                (chord, container.average[at: chord.onset]!.note)
            }
            if mapped.allSatisfy({ $0.0.note < $0.1 - spec.groupsMinimumMargin }) {
                chord.preferredHand = .left
            } else if mapped.allSatisfy({ $0.0.note > $0.1 + spec.groupsMinimumMargin }) {
                chord.preferredHand = .right
            }
        }
        
        struct Chords: RandomAccessCollection, ExpressibleByArrayLiteral {
            
            var contents: [Chord]
            var maxOffset: Double
            var preferredHand: Hand?
            
            var startIndex: Int { 0 }
            var endIndex: Int { contents.count }
            
            init(arrayLiteral elements: Chord...) {
                self.contents = elements
                self.maxOffset = elements.min(of: { $0.maxOffset ?? .greatestFiniteMagnitude }) ?? .greatestFiniteMagnitude
                
                if elements.allSatisfy({ $0.preferredHand == .left }) {
                    self.preferredHand = .left
                } else if elements.allSatisfy({ $0.preferredHand == .right }) {
                    self.preferredHand = .right
                }
            }
            
            subscript(position: Int) -> Chord {
                self.contents[position]
            }
            
        }
        
        /// Group by their maxOffset.
        let groups = chords.grouped(of: Chords.self) { i, chord, currentGroup, newGroup in
            if chord.max(of: \.onset)! < currentGroup.maxOffset,
               currentGroup.contents.reduce(0, { $0 + $1.count }) + chord.contents.count < spec.maxNoteCount {
                if currentGroup.preferredHand.isNil(or: { chord.preferredHand == $0 }) {
                    // okay, same hand
                } else {
                    currentGroup.preferredHand = nil
                }
                
                currentGroup.contents.append(chord)
                currentGroup.maxOffset = Swift.min(currentGroup.maxOffset, chord.maxOffset ?? .greatestFiniteMagnitude)
            } else {
                newGroup(&currentGroup)
                currentGroup = [chord]
            }
        }
        groups.forEach { index, group in
            // now, each group must be played by a single hand.
            
            for note in group.flatten() {
                note.velocity = UInt8(index % 10) * 12 + 1
            }
            
            if group.count == 1 {
                let chord = group[0]
                
                if let hand = chord.preferredHand {
                    chord.hand = hand
                    for note in chord {
                        note.channel = hand == .left ? 0 : 10
                    }
                } else {
                    let averageOnset = chord.average(of: \.onset)!
                    let average = container.average[at: averageOnset]!.note
                    let isLeftHand = chord.contains(where: { $0.note <= average })
                    
                    chord.hand = isLeftHand ? .left : .right
                    
                    for note in chord {
                        note.channel = isLeftHand ? 0 : 10
                    }
                }
            } else {
                if let hand = group.preferredHand {
                    for chord in group {
                        chord.hand = hand
                        for note in chord {
                            note.channel = hand == .left ? 0 : 10
                        }
                    }
                } else {
                    let min = group.min(of: { $0.min(of: \.note)! })!
                    let max = group.max(of: { $0.max(of: \.note)! })!
                    for chord in group {
                        if chord.contains(where: { $0.note == max }) {
                            chord.hand = .right
                            for note in chord {
                                note.channel = 10
                            }
                        } else if chord.contains(where: { $0.note == min }) {
                            chord.hand = .left
                            for note in chord {
                                note.channel = 0
                            }
                        } else {
                            // hand reachability?
                            for note in chord {
                                note.channel = 15
                            }
                        }
                    }
                }
            }
        }
        
        return chords
    }
    
    public struct Spec {
        
        /// The maximum distance apart to be considered within the same chord.
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
        
        /// The minimum distance for the group from average to be considered significant enough to change hand.
        let groupsMinimumMargin: UInt8 = 2
        
        public init() { }
        
    }
    
    public enum Hand {
        case left
        case right
    }
    
}


extension Chord: CustomDetailedStringConvertible {
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<Chord>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.contents)
            descriptor.optional(for: \.maxOffset)
            descriptor.optional(for: \.preferredHand)
            descriptor.optional(for: \.hand)
        }
    }
    
}


extension RandomAccessCollection where Index == Int {
    
    /// Custom grouping of `source`.
    ///
    /// Example:
    /// ```swift
    ///  Array.grouping(chords) { i, chord, currentGroup, newGroup in
    ///    if let firstChord = currentGroup.first {
    ///        if chord.min(of: \.onset)! - firstChord.max(of: \.onset)! < spec.duration {
    ///            currentGroup.append(chord)
    ///        } else {
    ///            newGroup(&currentGroup)
    ///            currentGroup = [chord]
    ///        }
    ///    } else {
    ///        currentGroup = [chord]
    ///    }
    /// }
    /// ```
    public func grouped<C>(
        of type: C.Type = [Element].self,
        update: (_ i: Int, _ element: Element, _ currentGroup: inout C, _ newGroup: (_ currentGroup: inout C) -> Void) -> Void
    ) -> [C] where C: RandomAccessCollection & ExpressibleByArrayLiteral, C.Element == Element {
        var groups: [C] = []
        var currentGroup: C = []
        
        var i = self.startIndex
        while i < self.endIndex {
            update(i, self[i], &currentGroup) { currentGroup in
                groups.append(currentGroup)
                currentGroup = []
            }
            
            i &+= 1
        }
        
        groups.append(currentGroup)
        return groups
    }
}

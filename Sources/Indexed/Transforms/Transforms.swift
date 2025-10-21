//
//  Transforms.swift
//  MIDIKit
//
//  Created by Vaida on 12/23/24.
//

import DetailedDescription
import Essentials


extension IndexedContainer {
    
    /// Applies the velocity info to `other`.
    ///
    /// This intended use case is when
    /// - `self` is transcribed by `PianoTranscription`
    ///   - velocity is correct but onset / offset is not
    /// - `other` is normalized by hand.
    ///   - velocity is incorrect.
    ///
    /// `self` will not be mutated.
    public func applyVelocity(to other: IndexedContainer) async {
        guard !self.isEmpty && !other.isEmpty else { return }
        
        for i in (21 as UInt8)...108 {
            guard let lhsNotes = self.notes[i],
                  let rhsNotes = other.notes[i] else { continue }
            
            var isLinked: Set<ReferenceNote> = []
            
            lhsNotes.forEach { index, lhs in
                guard let match = rhsNotes.nearest(to: lhs.onset, isValid: {
                    !isLinked.contains($0)
                }) else { return }
                isLinked.insert(match)
                lhs.velocity = match.velocity
            }
        }
    }
    
    /// Remove the artifacts that may have been created by PianoTranscription.
    ///
    /// - Parameters:
    ///   - threshold: The velocity of a note to be treated as artifact.
    ///
    /// - Returns: A new ``IndexedContainer`` initialized using the parameters used in the initializer for this instance. Contents of `self` remains unchanged.
    ///
    /// - Note: As `self` is a class, `self` is mutated on return.
    public func removingArtifacts(threshold: UInt8) async -> IndexedContainer {
        var contents: [MIDINote] = []
        contents.reserveCapacity(self.notes.count)
        
        var index = 21 as UInt8
        while index <= 108 {
            defer { index &+= 1 }
            guard var notes = self.notes[index]?.map(\.pointee) else { continue }
            var i = notes.count - 1
            var range: ClosedRange<Int>? = nil
            
            while i >= 0 {
                var isInCloseProximity: Bool {
                    let next = i &+ 1
                    guard next < notes.count else { return false }
                    let distance = notes[next].onset - notes[i].offset
                    return distance < 1/2 // 8th note
                }
                
                if notes[i].velocity <= threshold && i > 0 {
                    // update range
                    if range != nil {
                        if isInCloseProximity {
                            range = i...range!.upperBound
                        } else {
                            range = nil
                        }
                    } else {
                        range = i...i
                    }
                } else if let _range = range {
                    if isInCloseProximity {
                        // apply range
                        notes[i].offset = notes[_range.upperBound].offset
                        notes.removeSubrange(_range)
                        range = nil
                    } else {
                        range = nil
                    }
                } else {
                    range = nil
                }
                
                i &-= 1
            }
            
            contents.append(contentsOf: notes)
        }
        
        let container = MIDIContainer(tracks: [MIDITrack(notes: contents, sustains: self.sustains)])
        return IndexedContainer(container: container)
    }
    
    /// Apply the gap between consecutive notes.
    ///
    /// - Parameters:
    ///   - ideal: The ideal gap, defaults to 1/8 beat, 32th note in 4/4 120.
    ///   - minimumNoteLength: The minimum length of any resulting note.
    ///
    /// If ideal gap is not feasible, it will apply any adjustments it deems fit.
    public func applyGap(
        ideal: Double = 1/8,
        minimumNoteLength: Double = 1/128
    ) async {
        for i in 21...108 as ClosedRange<UInt8> {
            guard let contents = self.notes[i] else { continue }
            for i in 0..<contents.count - 1 {
                let duration = contents[i].duration
                let gap = contents[i + 1].onset - contents[i].offset
                let distance = duration + gap
                
                guard gap <= ideal else { continue } // no need to do anything.
                if distance > 2 * ideal { // able to fit ideal gap
                    contents[i].offset = contents[i + 1].onset - ideal
                } else if distance > minimumNoteLength { // ensure minimum note length
                    contents[i].offset = clamp(contents[i + 1].onset - ideal, min: contents[i].duration + minimumNoteLength)
                } // ensures nothing, keep as-is
            }
        }
    }
    
    /// Aligns the first note in the sequence to the start of the timeline (0:00:00).
    ///
    /// This function shifts all notes so that the earliest note starts exactly at time zero, preserving the relative timing between notes.
    public func alignFirstNoteToZero() async {
        let firstNoteOnset = self.contents.first?.onset ?? 0
        var i = self.contents.startIndex
        while i < self.contents.endIndex {
            self.contents[i].onset -= firstNoteOnset
            self.contents[i].offset -= firstNoteOnset
            i &+= 1
        }
        
        i = self.sustains.startIndex
        while i < self.sustains.endIndex {
            self.sustains[i].onset -= firstNoteOnset
            self.sustains[i].offset -= firstNoteOnset
            i &+= 1
        }
        
        self.sustains.contents.removeAll(where: { $0.onset < 0 })
    }
    
    /// Merge all notes that share the same interval in `other`.
    ///
    /// This function lookups the corresponding interval of every note in self (indicated by its center), if they share the same interval, they are merged.
    ///
    /// - Note: As `self` is a class, `self` is mutated on return.
    public func mergeNotesInSameInterval(in other: IndexedContainer) async -> IndexedContainer {
        var contents: [MIDINote] = []
        contents.reserveCapacity(self.notes.count)
        
        var index = 21 as UInt8
        while index <= 108 {
            defer { index &+= 1 }
            guard let notes = self.notes[index]?.map(\.pointee) else { continue }
            var iterator = notes.makeIterator()
            guard var prev = iterator.next() else { continue }
            var prevIndex = other.notes[index]?.index(at: prev.onset + prev.duration / 2)
            var _curr = iterator.next()
            
            while let curr = _curr {
                let currIndex = other.notes[index]?.index(at: curr.onset + curr.duration / 2)
                if let currIndex, currIndex == prevIndex {
                    prev.offset = curr.offset
                } else {
                    contents.append(prev)
                    prev = curr
                    prevIndex = currIndex
                }
                _curr = iterator.next()
            }
            
            // add prev anyway
            contents.append(prev)
        }
        
        let container = MIDIContainer(tracks: [MIDITrack(notes: contents, sustains: self.sustains)])
        return IndexedContainer(container: container)
    }
    
}

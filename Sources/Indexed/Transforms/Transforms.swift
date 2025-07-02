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
    public func applyVelocity(to other: IndexedContainer) {
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
    public func removingArtifacts(threshold: UInt8) -> IndexedContainer {
        var contents: [MIDINote] = []
        contents.reserveCapacity(self.notes.count)
        
        var index = 21 as UInt8
        while index < 108 {
            defer { index &+= 1 }
            guard var notes = self.notes[index]?.contents.map(\.pointee) else { continue }
            var i = notes.count - 1
            var range: ClosedRange<Int>? = nil
            
            while i > 0 {
                var isInCloseProximity: Bool {
                    let next = i &+ 1
                    guard next < notes.count else { return false }
                    let distance = notes[next].onset - notes[i].offset
                    return distance < 1/2 // 8th note
                }
                
                if notes[i].velocity < threshold {
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
    ///   - minimum: The minimum gap between consecutive notes.
    ///   - ideal: The ideal gap, defaults to 1/8 beat, 32th note in 4/4 120.
    ///   - minimumNoteLength: The minimum length of a resulting note.
    ///   - maxFractionOfDistance: The max gap, of fraction of difference of onsets.
    public func applyGap(
        minimum: Double = 1/128,
        ideal: Double = 1/8,
        minimumNoteLength: Double = 1/128,
        maxFractionOfDistance: Double = 1/2
    ) async {
        for i in 21...108 {
            guard let contents = self.notes[UInt8(i)] else { continue }
            for i in 0..<contents.count - 1 {
                let duration = contents[i].duration
                let gap = contents[i + 1].onset - contents[i].offset
                let distance = duration + gap
                
                let resultingGap: Double = clamp(ideal, min: gap, max: distance * maxFractionOfDistance)
                contents[i].offset = contents[i + 1].onset - clamp(resultingGap, min: minimum, max: distance - minimumNoteLength)
            }
        }
    }
    
    /// Aligns the first note in the sequence to the start of the timeline (0:00:00).
    ///
    /// This function shifts all notes so that the earliest note starts exactly at time zero, preserving the relative timing between notes.
    public func alignFirstNoteToZero() {
        let firstNoteOnset = self.contents.first?.onset ?? 0
        var i = self.contents.startIndex
        while i < self.contents.endIndex {
            self.contents[i].onset -= firstNoteOnset
            self.contents[i].offset -= firstNoteOnset
            i &+= 1
        }
        
        i = self.sustains.startIndex
        while i < self.sustains.endIndex {
            if self.sustains[i].onset - firstNoteOnset < 0 {
                // make it disappear
                self.sustains[i].onset = 0
                self.sustains[i].offset = 0
            } else {
                self.sustains[i].onset -= firstNoteOnset
                self.sustains[i].offset -= firstNoteOnset
            }
            i &+= 1
        }
    }
    
}

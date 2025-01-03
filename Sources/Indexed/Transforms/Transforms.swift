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
        guard !self.combinedNotes.isEmpty && !other.combinedNotes.isEmpty else { return }
        
        for i in (21 as UInt8)...108 {
            guard let lhsNotes = self.notes[i],
                  let rhsNotes = other.notes[i] else { continue }
            
            var isLinked: Set<UnsafeRawPointer> = []
            
            lhsNotes.forEach { index, lhs in
                guard let match = rhsNotes.nearest(to: lhs.onset, isValid: {
                    let pointer = Unmanaged.passUnretained($0).toOpaque()
                    return !isLinked.contains(pointer)
                }) else { return }
                let pointer = Unmanaged.passUnretained(match).toOpaque()
                isLinked.insert(pointer)
                lhs.velocity = match.velocity
            }
        }
    }
    
    /// Remove the artifacts that may have been created by PianoTranscription.
    ///
    /// - Parameters:
    ///   - threshold: The velocity of a note to be treated as artifact.
    ///
    /// - Returns: A new ``IndexedContainer`` initialized using the parameters used in the initializer for this instance.
    public func removingArtifacts(threshold: UInt8) async -> IndexedContainer {
        var contents: [UInt8 : DisjointNotes] = [:]
        contents.reserveCapacity(self.notes.count)
        
        for index in (21 as UInt8)...108 {
            guard var notes = self.notes[index]?.contents else { continue }
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
            contents[index] = DisjointNotes(notes)
        }
        
        return await IndexedContainer(notes: contents, sustains: self.sustains, runningLength: self.parameters.runningLength)
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
    
}

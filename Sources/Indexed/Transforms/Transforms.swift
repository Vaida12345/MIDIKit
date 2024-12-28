//
//  Transforms.swift
//  MIDIKit
//
//  Created by Vaida on 12/23/24.
//

import DetailedDescription


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
        var contents: [UInt8 : SingleNotes] = [:]
        contents.reserveCapacity(self.notes.count)
        
        for index in (21 as UInt8)...108 {
            guard var notes = self.notes[index]?.contents else { continue }
            var i = notes.count - 1
            var range: ClosedRange<Int>? = nil
            
            while i > 0 {
                if notes[i].velocity < threshold {
                    // update range
                    if range != nil {
                        range = i...range!.upperBound
                    } else {
                        range = i...i
                    }
                } else if let _range = range {
                    // apply range
                    notes[i].offset = notes[_range.upperBound].offset
                    notes.removeSubrange(_range)
                    range = nil
                }
                
                i &-= 1
            }
            contents[index] = SingleNotes(notes)
        }
        
        return await IndexedContainer(notes: contents, sustains: self.sustains, runningLength: self.parameters.runningLength)
    }
    
}

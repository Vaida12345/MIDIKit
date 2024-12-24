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
    
}

//
//  Normalize.swift
//  MIDIKit
//
//  Created by Vaida on 12/29/24.
//

import Essentials
import Foundation


extension IndexedContainer {
    
    /// Normalize the MIDI Container.
    ///
    /// This method is for MIDIs generated using PianoTranscription.
    ///
    /// This method will
    /// - ensure the gaps between consecutive notes (in the initializer)
    ///
    /// - Complexity: O(*n log n*), `makeChords`
    ///
    /// ## User-facing Description:
    /// Automatically adjusts note durations using the sustain pedal and nearby notes, fixing overly long notes and overlaps for more natural playback and clearer chords.
    ///
    /// - Adjusts note lengths to fix overlaps for clearer chords.
    public func normalize(preserve: PreserveSettings) {
        guard !self.isEmpty else { return }
        
        let chords = Chord.makeChords(from: self)
        let margin: Double = 1/4 // the padding after sustain
        let minimumLength: Double = Chord.Spec().duration
        
        chords.forEach { __index, chord in
            
            // check if normalization is required.
            // It is not required if there isn't any note in its duration
            if __index == chords.count - 1 { return }
            guard let nextNote = chords[__index + 1].min(of: \.onset) else { return }
            
            var indeterminate: Set<ReferenceNote> = []
            var reliableDeterminants: Set<ReferenceNote> = []
            
            /// Infers a single unresolved chord tone from notes whose offsets were explicitly bounded by normalization.
            ///
            /// This avoids using untouched AI-provided durations as evidence, because those durations are the common failure mode this pass is correcting.
            func inferSingleIndeterminateNote() {
                guard indeterminate.count == 1 else { return }
                let determinants = chord.contents.filter { reliableDeterminants.contains($0) && !indeterminate.contains($0) }
                guard !determinants.isEmpty else { return }
                guard let average = determinants.mean(of: \.offset) else { return }
                let removed = indeterminate.removeFirst()
                removed.offset = Swift.min(removed.offset, Swift.max(average, removed.onset + minimumLength))
            }
            
            chord.forEach { _, note in
                var isReliablyBounded = false
                
                // ensure the sustain is correct
                // The naming ignores the keyword `sustainRegion`,.
                let onsetIndex = sustains.index(at: note.onset)
                let onsetNextIndex = sustains.firstIndex(after: note.onset)
                let offsetIndex: Int?
                let offsetPreviousIndex = sustains.lastIndex(before: note.offset)
                let offsetNextIndex = sustains.firstIndex(after: note.offset)
                
                let onset = onsetIndex.map { sustains[$0] }
                let offset: MIDISustainEvent?
                let offsetPrevious = offsetPreviousIndex.map { sustains[$0] }
                let offsetNext = offsetNextIndex.map {sustains[$0] }
                
                if let region = sustains.index(at: note.offset) {
                    offsetIndex = region
                    offset = sustains[region]
                } else if let offsetPrevious,
                          offsetPrevious.offset > note.offset - margin,
                          offsetNext.isNil(or: { note.offset < $0.onset }),
                          note.onset <= offsetPrevious.offset { // Within margin, treat as offset sustain. Move the offset to the previous sustain region.
                    offset = offsetPrevious
                    offsetIndex = offsetPreviousIndex
                } else if let offsetPrevious, let offsetNext = sustains.first(after: note.offset),
                          offsetNext.onset - offsetPrevious.offset < margin * 2 { // the gap between sustains is extremely small, treat the gap as sustain reset.
                    offset = offsetPrevious
                    offsetIndex = offsetPreviousIndex
                } else if offsetNext == nil { // no next, it is the last sustain
                    offset = offsetPrevious
                    offsetIndex = offsetPreviousIndex
                } else {
                    offset = nil
                    offsetIndex = nil
                }
                
                
                if let onset, let offset {
                    // An sustain was found for offset & onset
                    if onset == offset {
                        // The onset and offset are in the same sustain region.
                        
                        // The length can be free.
                        // context aware length. Check for next note
                        setNoteOffset(clamp(note.offset, max: nextNote))
                        reliableDeterminants.insert(note)
                        return // no need to use proximity based method
                    } else if onsetNextIndex == offsetIndex && onsetNextIndex != nil {
                        // The onset and offset and in adjacent sustain regions.
                        span(offset)
                    } else {
                        // The note spans across 3 sustain regions
                        setExcessiveSpan()
                    }
                } else if let offset {
                    // An sustain was found for offset, but not onset
                    
                    if onsetNextIndex == offsetIndex && offsetIndex != nil {
                        // Sustain not found for offset, but the next sustain region is the offset sustain region
                        span(offset)
                    } else {
                        // The note spans across 2 sustain regions, without a leading sustain
                        setExcessiveSpan()
                    }
                } else if onsetIndex != nil {
                    // An sustain was found for onset, but not offset
                    inconclusiveNoOffset()
                } else {
                    // neither onset nor offset was found
                    
                    if onsetNextIndex != nil && onsetNextIndex == offsetNextIndex {
                        // there does not exist any sustains in the note region
                        switch preserve {
                        case .acousticResult:
                            // They are within the same non-sustained region. keep it as-is.
                            break
                        case .notesDisplay:
                            inconclusiveNoOffset()
                        }
                    } else if onsetNextIndex == offsetPreviousIndex {
                        // spanned one region.
                        
                        inconclusiveNoOffset()
                    } else {
                        // spanned more than one region
                        setExcessiveSpan()
                    }
                }
                
                
                func inconclusiveNoOffset() {
                    switch preserve {
                    case .acousticResult:
                        break
                    case .notesDisplay:
                        setNoteOffset(nextNote)
                    }
                    indeterminate.insert(note)
                }
                
                func setNoteOffset(_ value: Double) {
                    isReliablyBounded = true
                    note.offset = Swift.max(value, note.onset + minimumLength)
                }
                
                /// note has spanned at least three sustains
                func setExcessiveSpan() {
                    switch preserve {
                    case .acousticResult:
                        // leave it
                        break
                    case .notesDisplay:
                        // make it at least next sustain long
                        if let nextSustain = onsetNextIndex {
                            span(sustains[nextSustain])
                        } else {
                            assertionFailure("Should be a sustain")
                            setNoteOffset(clamp(note.offset, max: nextNote))
                        }
                    }
                    
                    indeterminate.insert(note)
                }
                
                /// Extends the note far enough to reach the found sustain while capping AI-transcribed tails.
                func span(_ sustain: MIDISustainEvents.Element) {
                    if sustain.onset < nextNote {
                        setNoteOffset(clamp(note.offset, min: sustain.onset + minimumLength))
                    } else {
                        switch preserve {
                        case .acousticResult:
                            setNoteOffset(
                                sustain.onset + minimumLength // ensure it is as short as possible
                            )
                        case .notesDisplay: setNoteOffset(clamp(nextNote, max: nextNote))
                        }
                    }
                }
                
                /// Trims an indeterminate note to the next nearby-pitch onset.
                ///
                /// Nearby notes are limited to a small pitch window so independent left-hand and right-hand durations do not force each other shorter.
                func applyProximityTrim() {
                    var nextProximateOnset: Double? = nil
                    for i in stride(from: Swift.max(0, Int(note.note) - 5), through: Int(note.note) + 5, by: 1) {
                        guard let proximateNote = self.notes[UInt8(i)]?.first(after: note.onset + minimumLength) else { continue }
                        
                        if nextProximateOnset == nil || nextProximateOnset! > proximateNote.onset {
                            nextProximateOnset = proximateNote.onset
                        }
                    }
                    
                    guard let nextProximateOnset else { return }
                    guard note.offset > nextProximateOnset else { return }
                    note.offset = nextProximateOnset
                }
                
                guard indeterminate.contains(note) else {
                    if isReliablyBounded {
                        reliableDeterminants.insert(note)
                    }
                    return
                }
                applyProximityTrim()
                
            } // forEach
            
            inferSingleIndeterminateNote()
        }
        
        // finally, make sure notes are not overlapping.
        for pitch in 21...108 as ClosedRange<UInt8> {
            guard let notes = self.notes[pitch] else { continue }
            
            var iterator = notes.makeIterator()
            var _curr = iterator.next()
            var _next = iterator.next()
            
            while let curr = _curr {
                guard let next = _next else { break }
                defer { _curr = next; _next = iterator.next() }
                
                curr.offset = clamp(curr.offset, min: curr.onset, max: Swift.max(next.onset - .leastNonzeroMagnitude, curr.onset + .leastNonzeroMagnitude))
            }
        }
    }
    
    
    public enum PreserveSettings: String, Equatable, Identifiable, CaseIterable, CustomLocalizedStringResourceConvertible, Sendable {
        /// Ensuring the sustains are correct for best acoustic results.
        case acousticResult = "Acoustic Result"
        /// Focusing on chords, minimize chords overlapping.
        case notesDisplay = "Notes Display"
        
        public var id: String {
            self.rawValue
        }
        
        public var localizedStringResource: LocalizedStringResource {
            switch self {
            case .acousticResult: "Acoustic Result"
            case .notesDisplay: "Notes Display"
            }
        }
        
        public var description: LocalizedStringResource {
            switch self {
            case .acousticResult:
                "Optimize note lengths using the sustain pedal for the most realistic sound."
            case .notesDisplay:
                "Tighten note lengths to reduce overlaps and make chords and rhythms easier to read."
            }
        }
    }
    
}

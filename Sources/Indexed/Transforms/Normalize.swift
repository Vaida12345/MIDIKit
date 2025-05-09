//
//  Normalize.swift
//  MIDIKit
//
//  Created by Vaida on 12/29/24.
//

import Essentials


extension IndexedContainer {
    
    /// Normalize the MIDI Container.
    ///
    /// This method is for MIDIs generated using PianoTranscription.
    ///
    /// This method will
    /// - ensure the gaps between consecutive notes (in the initializer)
    public func normalize(preserve: PreserveSettings) async {
        guard !self.isEmpty else { return }
        
        let chords = await Chord.makeChords(from: self)
        let margin: Double = 1/4 // the padding after sustain
        let minimumLength: Double = 1/64
        
        chords.forEach { __index, chord in
            
            // check if normalization is required.
            // It is not required if there isn't any note in its duration
            if __index == chords.count - 1 { return }
            let nextNote = chords[__index + 1].min(of: \.onset)!
            chord.forEach { _, note in
                
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
                        setNoteOffset(
                            clamp(note.offset, max: nextNote),
                            channel: 0
                        )
                    } else if onsetNextIndex! == offsetIndex! {
                        // The onset and offset and in adjacent sustain regions.
                        span(offset)
                    } else {
                        // The note spans across 3 sustain regions
                        setExcessiveSpan(channel: 3)
                    }
                } else if let offset {
                    // An sustain was found for offset, but not onset
                    
                    if onsetNextIndex! == offsetIndex! {
                        // Sustain not found for offset, but the next sustain region is the offset sustain region
                        span(offset)
                    } else {
                        // The note spans across 2 sustain regions, without a leading sustain
                        setExcessiveSpan(channel: 5)
                    }
                } else if let onsetIndex {
                    // An sustain was found for onset, but not offset
                    inconclusiveNoOffset(channel: 6)
                } else {
                    // neither onset nor offset was found
                    
                    if onsetNextIndex != nil && onsetNextIndex == offsetNextIndex {
                        // there does not exist any sustains in the note region
                        switch preserve {
                        case .acousticResult:
                            // They are within the same non-sustained region. keep it as-is.
                            debugChannel(7)
                        case .notesDisplay:
                            inconclusiveNoOffset(channel: 8)
                        }
                    } else if onsetNextIndex == offsetPreviousIndex, let offsetPrevious {
                        // spanned one region.
                        
                        inconclusiveNoOffset(channel: 9)
                    } else {
                        // spanned more than one region
                        setExcessiveSpan(channel: 15)
                    }
                }
                
                
                func inconclusiveNoOffset(channel: UInt8) {
                    switch preserve {
                    case .acousticResult:
                        debugChannel(channel)
                    case .notesDisplay:
                        setNoteOffset(
                            clamp(nextNote, max: nextNote),
                            channel: channel
                        )
                    }
                }
                
                func setNoteOffset(_ value: Double, channel: UInt8) {
                    note.offset = max(value, note.onset + minimumLength)
                    debugChannel(channel)
                }
                
                /// note has spanned at least three sustains
                func setExcessiveSpan(channel: UInt8) {
                    guard preserve == .acousticResult else {
                        // The note has spanned at least three sustains, consider this a duration error.
                        setNoteOffset(
                            clamp(note.offset, max: nextNote),
                            channel: channel
                        )
                        return
                    }
                    
                    let average = self.average[at: note.onset]!
                    if note.note < average.note {
                        // maybe this is the left hand, leave it. For example, Moonlight I.
                    } else {
                        setNoteOffset(
                            clamp(note.offset, max: nextNote),
                            channel: channel
                        )
                    }
                }
                
                /// note length must span to the found sustain.
                func span(_ sustain: MIDISustainEvents.Element) {
                    if sustain.onset < nextNote {
                        setNoteOffset(
                            clamp(note.offset, min: sustain.onset + minimumLength, max: nextNote),
                            channel: 1
                        )
                    } else {
                        switch preserve {
                        case .acousticResult:
                            setNoteOffset(
                                sustain.onset + minimumLength, // ensure it is as short as possible
                                channel: 2
                            )
                        case .notesDisplay: setNoteOffset(
                            clamp(nextNote, max: nextNote),
                            channel: 2
                        )
                        }
                    }
                }
                
                func debugChannel(_ channel: UInt8) {
#if DEBUG
                    note.channel = channel
#endif
                }
                
            }
        }
    }
    
    
    public enum PreserveSettings: String, Equatable, Identifiable, CaseIterable {
        /// Ensuring the sustains are correct for best acoustic results.
        case acousticResult = "Acoustic Result"
        /// Focusing on chords, minimize chords overlapping.
        case notesDisplay = "Notes Display"
        
        public var id: String {
            self.rawValue
        }
    }
    
}

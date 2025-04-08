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
        guard !self.combinedNotes.isEmpty else { return }
        
        let chords = await Chord.makeChords(from: self)
        let margin: Double = 1/16 // the padding after sustain
        
        chords.forEach {
            __index,
            chord in
            // check if normalization is required.
            // It is not required if there isn't any note in its duration
            if __index == chords.count - 1 { return }
            let nextOnset = chords[__index + 1].min(of: \.onset)!
            chord.forEach {
                _,
                note in
#if DEBUG
                defer {
                    print(note)
                }
#endif
                // ensure the sustain is correct
                // The naming ignores the keyword `sustainRegion`,.
                let onsetIndex = sustains.index(at: note.onset)
                let onsetNextIndex = sustains.firstIndex(after: note.onset)
                let offsetIndex: Int?
                let offsetPreviousIndex = sustains.lastIndex(before: note.offset)
                
                let onset = onsetIndex.map { sustains[$0] }
                let offset: MIDISustainEvent?
                let offsetPrevious = offsetPreviousIndex.map { sustains[$0] }
                
                if let region = sustains.index(at: note.offset) {
                    offsetIndex = region
                    offset = sustains[region]
                } else if let offsetPrevious,
                          offsetPrevious.offset > note.offset - margin,
                          note.onset <= offsetPrevious.offset { // Within margin, treat as offset sustain
                    offset = offsetPrevious
                    offsetIndex = offsetPreviousIndex
                } else {
                    offset = nil
                    offsetIndex = nil
                }
                
                
                if let offset {
                    // An sustain was found for offset, or within margin
                    
                    if let onset {
                        // An sustain was found for offset & onset
                        
                        if onset == offset {
                            // The onset and offset are in the same sustain region.
                            
                            // The length can be free.
                            //                note.duration = minimumLength
                            // context aware length. Check for next note
                            setNoteOffset(
                                min(note.offset, nextOnset),
                                channel: 0
                            )
                        } else if onsetNextIndex! == offsetIndex! {
                            // The onset and offset and in adjacent sustain regions.
                            
                            span(offset)
                        } else {
                            setExcessiveSpan(channel: 3)
                        }
                    } else {
                        // An sustain was found for offset, but not onset
                        
                        if onsetNextIndex! == offsetIndex! {
                            // Sustain not found for offset, but the next sustain region is the offset sustain region
                            span(offset)
                        } else {
                            setExcessiveSpan(channel: 5)
                        }
                    }
                } else if let onsetIndex {
                    // An sustain was found for onset, but not offset
                    if let offsetPreviousIndex,
                       onsetIndex <= offsetPreviousIndex {
                        // spanned exacted half region.
                        if let offsetNext = sustains.first(after: note.offset),
                           let offsetPrevious,
                           nextOnset < offsetNext.onset && nextOnset > offsetPrevious.onset {
                            // crop anyway
                            setNoteOffset(nextOnset, channel: 6)
                        } else if let onsetNextIndex,
                                  onsetNextIndex < offsetPreviousIndex {
                            setExcessiveSpan(channel: 7)
                        } else {
                            setExcessiveSpan(channel: 8)
                        }
                    } else {
                        setExcessiveSpan(channel: 9)
                    }
                } else {
                    // do not change it, this is the initial chord, or its offset is too far from the previous sustain.
                    // nether onset nor offset was found
                    if onsetNextIndex != nil && onsetNextIndex == sustains.firstIndex(after: note.offset) {
                        switch preserve {
                        case .acousticResult:
                            // They are within the same non-sustained region. keep it as-is.
#if DEBUG
                            note.channel = 10
#endif
                            break
                        case .notesDisplay:
                            setNoteOffset(
                                nextOnset,
                                channel: 11
                            )
                        }
                    } else if onsetNextIndex == offsetPreviousIndex {
                        // spanned exacted one region.
                        if let offsetNext = sustains.first(after: note.offset),
                           let offsetPrevious {
                            if nextOnset < offsetNext.onset && nextOnset > offsetPrevious.onset {
                                // crop anyway
                                setNoteOffset(
                                    nextOnset,
                                    channel: 12
                                )
                            } else {
#if DEBUG
                                note.channel = 13
#endif
                            }
                        } else {
#if DEBUG
                            note.channel = 14
#endif
                        }
                    } else {
                        setExcessiveSpan(channel: 15)
                    }
                }
                
                func setNoteOffset(_ value: Double, channel: UInt8) {
                    note.offset = max(value, note.onset + 1/64)
#if DEBUG
                    note.channel = channel
#endif
                }
                
                /// note has spanned at least three sustains
                func setExcessiveSpan(channel: UInt8) {
                    guard preserve == .acousticResult else {
                        // The note has spanned at least three sustains, consider this a duration error.
                        setNoteOffset(nextOnset, channel: channel)
                        return
                    }
                    
                    let average = self.average[at: note.onset]!
                    if note.note < average.note {
                        // maybe this is the left hand, leave it. For example, Moonlight I.
                    } else {
                        setNoteOffset(nextOnset, channel: channel)
                    }
                }
                
                /// note length must span to the found sustain.
                func span(_ sustain: MIDISustainEvents.Element) {
                    
                    let nextSustainRegionStart = note.offset < sustain.onset + margin ? sustain.onset : sustain.onset + margin
                    if nextSustainRegionStart < nextOnset {
                        setNoteOffset(
                            clamp(note.offset, min: nextSustainRegionStart, max: nextOnset),
                            channel: 1
                        )
                    } else {
                        switch preserve {
                        case .acousticResult:
                            setNoteOffset(
                                nextSustainRegionStart,
                                channel: 2
                            )
                        case .notesDisplay: setNoteOffset(
                            nextOnset,
                            channel: 2
                        )
                        }
                    }
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

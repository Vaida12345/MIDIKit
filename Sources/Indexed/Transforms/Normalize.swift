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
        
        chords.forEach { __index, chord in
            // check if normalization is required.
            // It is not required if there isn't any note in its duration
            if __index == chords.count - 1 { return }
            let nextOnset = chords[__index + 1].min(of: \.onset)!
            chord.forEach { _, note in
#if DEBUG
                defer {
                    print(note)
                }
#endif
                // ensure the sustain is correct
                let onsetSustainIndex = sustains.index(at: note.onset)
                let onsetSustainRegion = onsetSustainIndex.map { sustains[$0] }
                let offsetPreviousIndex = sustains.lastIndex(before: note.offset)
                let offsetPrevious = offsetPreviousIndex.map { sustains[$0] }
                let onsetNextIndex = sustains.firstIndex(after: note.onset)
                let offsetSustainRegion: MIDISustainEvent?
                let offsetSustainIndex: Int?
                if let region = sustains.index(at: note.offset) {
                    offsetSustainIndex = region
                    offsetSustainRegion = sustains[region]
                } else if let offsetPrevious, offsetPrevious.offset > note.offset - margin, note.onset <= offsetPrevious.offset { // Within margin, treat as offset sustain
                    offsetSustainRegion = offsetPrevious
                    offsetSustainIndex = offsetPreviousIndex
                } else {
                    offsetSustainRegion = nil
                    offsetSustainIndex = nil
                }
                
                func setNoteOffset(_ value: Double) {
                    note.offset = max(value, note.onset + 1/64)
                }
                
                /// note has spanned at least three sustains
                func setExcessiveSpan() {
#if DEBUG
                    note.channel = 4
#endif
                    guard preserve == .acousticResult else {
                        // The note has spanned at least three sustains, consider this a duration error.
                        setNoteOffset(nextOnset)
                        return
                    }
                    
                    let average = self.average[at: note.onset]!
                    if note.note < average.note {
                        // maybe this is the left hand, leave it. For example, Moonlight I.
                    } else {
                        setNoteOffset(nextOnset)
                    }
                }
                
                if let offsetSustainRegion {
                    // An sustain was found for offset, or within margin
                    
                    if let onsetSustainRegion {
                        // An sustain was found for offset & onset
                        
                        if onsetSustainRegion == offsetSustainRegion {
                            // The onset and offset are in the same sustain region.
                            
                            // The length can be free.
                            //                note.duration = minimumLength
                            // context aware length. Check for next note
                            setNoteOffset(min(note.offset, nextOnset))
#if DEBUG
                            note.channel = 0
#endif
                        } else if onsetNextIndex! == offsetSustainIndex! {
                            // The onset and offset and in adjacent sustain regions.
                            // the length must span to the found sustain.
                            
                            let nextSustainRegionStart = note.offset < offsetSustainRegion.onset + margin ? offsetSustainRegion.onset : offsetSustainRegion.onset + margin
                            if nextSustainRegionStart < nextOnset {
                                setNoteOffset(clamp(note.offset, min: nextSustainRegionStart, max: nextOnset))
#if DEBUG
                                note.channel = 1
#endif
                            } else {
                                switch preserve {
                                case .acousticResult: setNoteOffset(nextSustainRegionStart)
                                case .notesDisplay: setNoteOffset(nextOnset)
                                }
#if DEBUG
                                note.channel = 2
#endif
                            }
                        } else {
                            setExcessiveSpan()
                        }
                    } else {
                        // An sustain was found for offset, but not onset
                        
                        if onsetNextIndex! == offsetSustainIndex! {
                            // Sustain not found for offset, but the next sustain region is the offset sustain region
                            // the length must span to the found sustain.
                            
                            let nextSustainRegionStart = note.offset < offsetSustainRegion.onset + margin ? offsetSustainRegion.onset : offsetSustainRegion.onset + margin
                            
                            setNoteOffset(nextSustainRegionStart)
#if DEBUG
                            note.channel = 3
#endif
                        } else {
#if DEBUG
                            note.channel = 5
#endif
                            setExcessiveSpan()
                        }
                    }
                } else if let onsetSustainIndex {
                    // An sustain was found for onset, but not offset
                    if let offsetPreviousIndex, onsetSustainIndex <= offsetPreviousIndex {
                        // spanned exacted half region.
                        if let offsetNext = sustains.first(after: note.offset), let offsetPrevious,
                           nextOnset < offsetNext.onset && nextOnset > offsetPrevious.onset {
                            // crop anyway
#if DEBUG
                            note.channel = 6
#endif
                            setNoteOffset(nextOnset)
                        } else if let onsetNextIndex, onsetNextIndex < offsetPreviousIndex {
#if DEBUG
                            note.channel = 7
#endif
                            setExcessiveSpan()
                        } else {
                            setExcessiveSpan()
#if DEBUG
                            note.channel = 8
#endif
                        }
                    } else {
#if DEBUG
                        note.channel = 10
#endif
                        setExcessiveSpan()
                    }
                } else {
                    // do not change it, this is the initial chord, or its offset is too far from the previous sustain.
                    // nether onset nor offset was found
                    if onsetNextIndex != nil && onsetNextIndex == sustains.firstIndex(after: note.offset) {
                        switch preserve {
                        case .acousticResult:
                            // They are within the same non-sustained region. keep it as-is.
                            break
                        case .notesDisplay:
                            setNoteOffset(nextOnset)
                        }
#if DEBUG
                        note.channel = 11
#endif
                    } else if onsetNextIndex == offsetPreviousIndex {
                        // spanned exacted one region.
                        if let offsetNext = sustains.first(after: note.offset), let offsetPrevious {
                            if nextOnset < offsetNext.onset && nextOnset > offsetPrevious.onset {
                                // crop anyway
                                setNoteOffset(nextOnset)
#if DEBUG
                                note.channel = 12
#endif
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
                        setExcessiveSpan()
#if DEBUG
                        note.channel = 15
#endif
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

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
    public func normalize(preserve: PreserveSettings = .acousticResult) async {
        guard !self.combinedNotes.isEmpty else { return }
        
        let chords = await Chord.makeChords(from: self)
        let margin: Double = 1/16 // the padding after sustain
        
        chords.forEach { __index, chord in
            // check if normalization is required.
            // It is not required if there isn't any note in its duration
            if __index == chords.count - 1 { return }
            let nextOnset = chords[__index + 1].min(of: \.onset)!
            chord.forEach { _, note in
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
                            note.channel = 0
                        } else if onsetNextIndex! == offsetSustainIndex! {
                            // the length must span to the found sustain.
                            
                            let minimum = note.offset < offsetSustainRegion.onset + margin ? offsetSustainRegion.onset : offsetSustainRegion.onset + margin
                            let maximum = nextOnset
                            if minimum < maximum {
                                setNoteOffset(clamp(note.offset, min: minimum, max: maximum))
                                note.channel = 1
                            } else {
                                switch preserve {
                                case .acousticResult: setNoteOffset(minimum)
                                case .notesDisplay: setNoteOffset(maximum)
                                }
                                note.channel = 2
                            }
                        } else {
                            setExcessiveSpan()
                        }
                    } else {
                        // An sustain was found for offset, but not onset
                        
                        if onsetNextIndex! == offsetSustainIndex! {
                            // the length must span to the found sustain.
                            
                            let minimum = note.offset < offsetSustainRegion.onset + margin ? offsetSustainRegion.onset : offsetSustainRegion.onset + margin
                            let maximum = nextOnset
                            if minimum < maximum {
                                setNoteOffset(clamp(note.offset, min: minimum, max: maximum))
                                note.channel = 3
                            } else {
                                switch preserve {
                                case .acousticResult: setNoteOffset(minimum)
                                case .notesDisplay: setNoteOffset(maximum)
                                }
                                note.channel = 4
                            }
                        } else {
                            note.channel = 5
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
                            note.channel = 6
                            setNoteOffset(nextOnset)
                        } else if let onsetNextIndex, onsetNextIndex < offsetPreviousIndex {
                            note.channel = 7
                            setExcessiveSpan()
                        } else {
                            setExcessiveSpan()
                            note.channel = 8
                        }
                    } else {
                        note.channel = 10
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
                        note.channel = 11
                    } else if onsetNextIndex == offsetPreviousIndex {
                        // spanned exacted one region.
                        if let offsetNext = sustains.first(after: note.offset), let offsetPrevious {
                            if nextOnset < offsetNext.onset && nextOnset > offsetPrevious.onset {
                                // crop anyway
                                setNoteOffset(nextOnset)
                                note.channel = 12
                            } else {
                                note.channel = 13
                            }
                        } else {
                            note.channel = 14
                        }
                    } else {
                        setExcessiveSpan()
                        note.channel = 15
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

//
//  IndexedContainer.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Essentials
import ConcurrentStream


/// Container supporting efficient lookup.
public struct IndexedContainer {
    
    /// Key: 21...108
    public var notes: [UInt8 : IndexedNotes]
    
    /// The `combinedNotes` and `notes` share the same reference.
    public var combinedNotes: IndexedNotes
    
    public var sustains: MIDISustainEvents
    
    public var average: RunningAverage
    
    
    /// Normalize the MIDI Container.
    ///
    /// This method is for MIDIs generated using PianoTranscription.
    ///
    /// This method will
    /// - ensure the gaps between consecutive notes (in the initializer)
    public func normalize(preserve: PreserveSettings = .acousticResult) async throws {
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
                    if chord.contains(where: { $0.note < average.note }) {
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
                        } else if onsetNextIndex! == offsetSustainIndex! {
                            // the length must span to the found sustain.
                            
                            let minimum = note.offset < offsetSustainRegion.onset + margin ? offsetSustainRegion.onset : offsetSustainRegion.onset + margin
                            let maximum = nextOnset
                            if minimum < maximum {
                                setNoteOffset(clamp(note.offset, min: minimum, max: maximum))
                            } else {
                                switch preserve {
                                case .acousticResult: setNoteOffset(minimum)
                                case .notesDisplay: setNoteOffset(maximum)
                                }
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
                            } else {
                                switch preserve {
                                case .acousticResult: setNoteOffset(minimum)
                                case .notesDisplay: setNoteOffset(maximum)
                                }
                            }
                        } else {
                            setExcessiveSpan()
                        }
                    }
                } else if let onsetSustainIndex {
                    // An sustain was found for onset, but not offset
                    if onsetSustainIndex == offsetPreviousIndex {
                        // spanned exacted half region.
                        if let offsetNext = sustains.first(after: note.offset), let offsetPrevious {
                            if nextOnset < offsetNext.onset && nextOnset > offsetPrevious.onset {
                                // crop anyway
                                setNoteOffset(nextOnset)
                            } else {
                                
                            }
                        } else {
                            
                        }
                    } else {
                        setExcessiveSpan()
                    }
                } else {
                    // do not change it, this is the initial chord, or its offset is too far from the previous sustain.
                    // nether onset nor offset was found
                    if onsetNextIndex != nil && onsetNextIndex == sustains.firstIndex(after: note.offset) {
                        // They are within the same non-sustained region. keep it as-is.
                    } else if onsetNextIndex == offsetPreviousIndex {
                        // spanned exacted one region.
                        if let offsetNext = sustains.first(after: note.offset), let offsetPrevious {
                            if nextOnset < offsetNext.onset && nextOnset > offsetPrevious.onset {
                                // crop anyway
                                setNoteOffset(nextOnset)
                            } else {
                                
                            }
                        } else {
                            
                        }
                    } else {
                        setExcessiveSpan()
                    }
                }
            }
        }
    }
    
    public func makeContainer() -> MIDIContainer {
        let track = MIDITrack(notes: MIDINotes(notes: self.combinedNotes.map(\.content)), sustains: self.sustains)
        return MIDIContainer(tracks: [track])
    }
    
    
    /// - Parameter minimumConsecutiveNoteGap: The default value is `1/128`. The minimum length of individual note from La campanella in G-Sharp Minor by Lang Lang is 0.013 beat, which is around 1/64 beat.
    public init(container: MIDIContainer, minimumConsecutiveNoteGap: Double = 1/128) async {
        self.sustains = MIDISustainEvents(sustains: container.tracks.flatMap(\.sustains))
        
        let notes = container.tracks.flatMap(\.notes).map(ReferenceNote.init)
        let combinedNotes = IndexedNotes(contents: notes.sorted(by: { $0.onset < $1.onset }))
        async let average = await RunningAverage(combinedNotes: combinedNotes)
        
        let grouped = Dictionary(grouping: notes, by: \.note)
        
        var dictionary: [UInt8 : IndexedNotes] = [:]
        dictionary.reserveCapacity(88)
        for i in 21...108 {
            let contents = grouped[UInt8(i)]?.sorted { $0.onset < $1.onset } ?? []
            for i in 0..<contents.count {
                // ensures non-overlapping
                if i > contents.count - 1 {
                    contents[i].offset = min(contents[i].offset, contents[i + 1].onset - minimumConsecutiveNoteGap)
                }
            }
            
            dictionary[UInt8(i)] = IndexedNotes(contents: contents)
        }
        
        self.notes = dictionary
        self.combinedNotes = combinedNotes
        self.average = await average
    }
    
    public enum PreserveSettings {
        /// Ensuring the sustains are correct for best acoustic results.
        case acousticResult
        /// Focusing chords, minimise chords overlapping.
        case notesDisplay
    }
    
}


extension MIDIContainer {
    
    public func indexed() async -> IndexedContainer {
        await IndexedContainer(container: self)
    }
    
}

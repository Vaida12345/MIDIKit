//
//  IndexedContainer.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//


/// Container supporting efficient lookup.
public struct IndexedContainer {
    
    /// Key: 21...108
    public var notes: [UInt8 : IndexedNotes]
    
    /// The `combinedNotes` and `notes` share the same reference.
    public var combinedNotes: IndexedNotes
    
    public var sustains: MIDISustainEvents
    
    
    /// Normalize the MIDI Container.
    ///
    /// This method is for MIDIs generated using PianoTranscription.
    ///
    /// This method will
    /// - ensure the gaps between consecutive notes (in the initializer)
    public mutating func normalize() async {
        let chords = Chord.makeChords(from: self)
        let minimumLength: Double = 1/64 // the padding after sustain
        
        chords.forEach { offset, current in
            // check if normalization is required.
            // It is not required if there isn't any note in its duration
            if offset == chords.count - 1 { return }
            let next = chords[offset + 1]
            let onset = next.min(of: \.onset)!
            for note in current {
                // ensure the sustain is correct
                let onsetSustainRegion = sustains[at: note.onset]
                let offsetSustainRegion = sustains[at: note.offset] ?? sustains.last(before: note.offset)
             
                if onsetSustainRegion == offsetSustainRegion || offsetSustainRegion == nil {
                    // The length can be free.
                    //                note.duration = minimumLength
                    // context aware length. Check for next note
                    note.offset = min(note.offset, onset)
                } else {
                    // the length must span to the found sustain.
                    note.offset = max(offsetSustainRegion!.onset + minimumLength, note.offset)
                }
            }
        }
    }
    
    public func makeContainer() -> MIDIContainer {
        let track = MIDITrack(notes: MIDINotes(notes: self.combinedNotes.map(\.content)), sustains: self.sustains)
        return MIDIContainer(tracks: [track])
    }
    
    
    public init(container: MIDIContainer) async {
        self.sustains = MIDISustainEvents(sustains: container.tracks.flatMap(\.sustains))
        let notes = container.tracks.flatMap(\.notes).map(ReferenceNote.init)
        let grouped = Dictionary(grouping: notes, by: \.note)
        
        var dictionary: [UInt8 : IndexedNotes] = [:]
        dictionary.reserveCapacity(88)
        for i in 21...108 {
            let contents = grouped[UInt8(i)]?.sorted { $0.onset < $1.onset } ?? []
            for i in 0..<contents.count {
                // ensures non-overlapping
                if i > contents.count - 1 {
                    contents[i].offset = min(contents[i].offset, contents[i + 1].onset - IndexedContainer.spec.minimumConsecutiveNoteGap)
                }
            }
            
            dictionary[UInt8(i)] = IndexedNotes(contents: contents)
        }
        
        self.notes = dictionary
        self.combinedNotes = IndexedNotes(contents: notes)
    }
    
    
    /// Unless specified otherwise, all measurements are in beats.
    public struct NormalizationSpec {
        
        /// The default value is 1/128 beat
        ///
        /// The minimum length of individual note from La campanella in G-Sharp Minor by Lang Lang is 0.013 beat, which is around 1/64 beat.
        public let minimumConsecutiveNoteGap: Double = 1/128
        
    }
    
    static var spec: NormalizationSpec {
        NormalizationSpec()
    }
    
}


extension MIDIContainer {
    
    public func indexed() async -> IndexedContainer {
        await IndexedContainer(container: self)
    }
    
}

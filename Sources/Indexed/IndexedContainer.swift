//
//  IndexedContainer.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//


/// Container supporting efficient lookup.
public struct IndexedContainer {
    
    /// Key: 21...108
    var notes: [UInt8 : IndexedNotes]
    
    /// The `combinedNotes` and `notes` share the same reference.
    var combinedNotes: IndexedNotes
    
    var sustains: MIDISustainEvents
    
    
    /// Normalize the MIDI Container.
    ///
    /// This method is for MIDIs generated using PianoTranscription.
    ///
    /// This method will
    /// - ensure the gaps between consecutive notes (in the initializer)
    public mutating func normalize() {
//        for (offset, current) in combinedNotes.enumerated() {
//            
//            // check if normalization is required.
//            // It is not required if there isn't any note in its duration
//            if offset == combinedNotes.count { continue }
//            let next = combinedNotes[offset + 1]
//            if next.onset >= current.offset { continue }
//            
//            
//        }
        
//        let chords = Chord.makeChords(from: self)
//        for (offset, current) in chords.enumerated() {
//
//            // check if normalization is required.
//            // It is not required if there isn't any note in its duration
//            if offset == chords.count { continue }
//            let next = chords[offset + 1]
//            if next.maxOffset >= current.offset { continue }
//
//
//        }
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

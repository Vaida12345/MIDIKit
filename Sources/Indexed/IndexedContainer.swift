//
//  IndexedContainer.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Foundation
import Essentials


/// Container supporting efficient lookup.
///
/// In the implementation, methods that involve insertion or removal of notes returns a new container, as this structure has two properties containing the notes, for efficient lookup.
public final class IndexedContainer {
    
    /// The notes grouped by the key.
    ///
    /// None value is represented by `nil` (instead of empty array)
    ///
    /// Key: 21...108
    public let notes: [UInt8 : DisjointNotes]
    
    /// Sorted notes
    public let contents: UnsafeMutableBufferPointer<MIDINote>
    
    /// The sustain events.
    public var sustains: MIDISustainEvents
    
    
    /// Whether the container is empty
    @inlinable
    public var isEmpty: Bool {
        self.contents.isEmpty
    }
    
    /// Number of notes in the container.
    @inlinable
    public var count: Int {
        self.contents.count
    }
    
    
    /// Converts the indexed container back to ``MIDIContainer``.
    @inlinable
    public func makeContainer() -> MIDIContainer {
        let notes = [MIDINote](unsafeUninitializedCapacity: self.count) {
            self.contents.copy(to: $0.baseAddress!, count: self.count)
            $1 = self.count
        }
        
        let track = MIDITrack(notes: MIDINotes(consume notes), sustains: self.sustains)
        return MIDIContainer(tracks: [track])
    }
    
    /// - Parameters:
    ///   - container: The source container.
    ///   - minimumConsecutiveNotesGap: The minimum gap between two consecutive notes. The default value is `1/128`. The minimum length of individual note from La campanella in G-Sharp Minor by Lang Lang is 0.013 beat, which is around 1/64 beat.
    ///   - runningLength: The length for calculating the running average. The default value is `4` beats, that is one measure in a 4/4 sheet.
    ///
    /// Any methods that returns a new ``IndexedContainer`` will use the parameters set in the initializer.
    @inlinable
    public init(
        container: MIDIContainer,
        minimumConsecutiveNotesGap: Double = 1/128
    ) {
        let contents: UnsafeMutableBufferPointer<MIDINote>
        let sustains: MIDISustainEvents
        
        if container.tracks.count == 1,
           let track = container.tracks.first {
            var notes = track.notes.contents
            notes.sort { $0.onset < $1.onset }
            contents = .allocate(capacity: notes.count)
            memcpy(contents.baseAddress!, &notes, MemoryLayout<MIDINote>.stride * notes.count)
            
            sustains = track.sustains
        } else {
            var notes = container.tracks.flatMap(\.notes)
            notes.sort { $0.onset < $1.onset }
            contents = .allocate(capacity: notes.count)
            memcpy(contents.baseAddress!, &notes, MemoryLayout<MIDINote>.stride * notes.count)
            
            sustains = MIDISustainEvents(container.tracks.flatMap(\.sustains))
        }
        
        self.contents = contents
        self.sustains = sustains
        
        // construct grouped
        var grouped: [UInt8 : [ReferenceNote]] = [:]
        contents.forEach { index, element in
            grouped[element.note, default: []].append(contents.baseAddress! + index)
        }
        
        
        // construct dictionary
        var dictionary: [UInt8 : DisjointNotes] = [:]
        var index = 0 as UInt8
        while index < 108 {
            defer { index &+= 1 }
            guard let contents = grouped[index] else { continue }
            var i = 0
            while i < contents.count - 1 {
                // ensures non-overlapping
                contents[i].offset = min(contents[i].offset, contents[i + 1].onset - minimumConsecutiveNotesGap)
                i &+= 1
            }
            
            guard !contents.isEmpty else { continue }
            dictionary[index] = DisjointNotes(contents)
        }
        _ = consume grouped
        
        self.notes = dictionary
    }
    
    @inlinable
    deinit {
        self.contents.deallocate()
    }
    
}


extension MIDIContainer {
    
    /// Converts the container to ``IndexedContainer``.
    ///
    /// - Parameters:
    ///   - minimumConsecutiveNotesGap: The minimum gap between two consecutive notes. The default value is `1/128`. The minimum length of individual note from La campanella in G-Sharp Minor by Lang Lang is 0.013 beat, which is around 1/64 beat.
    ///
    /// Any methods that returns a new ``IndexedContainer`` will use the parameters set in the initializer.
    @inlinable
    public func indexed(
        minimumConsecutiveNotesGap: Double = 1/128
    ) -> IndexedContainer {
        IndexedContainer(
            container: self,
            minimumConsecutiveNotesGap: minimumConsecutiveNotesGap
        )
    }
    
}


extension UnsafeMutableBufferPointer<MIDINote>: SortedIntervals, OverlappingIntervals {
    
}

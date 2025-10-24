//
//  IndexedContainer.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Foundation
import Essentials
import Optimization


/// Container supporting efficient lookup.
///
/// In the implementation, methods that involve insertion or removal of notes returns a new container, as this structure has two properties containing the notes, for efficient lookup.
public final class IndexedContainer {
    
    /// The notes grouped by the key.
    ///
    /// None value is represented by `nil` (instead of empty array)
    ///
    /// - Warning: The `DisjointNote`s holds unowned references to `self.contents`, please make sure you hold `self` to use `DisjointNote`s.
    ///
    /// Key: 21...108
    public fileprivate(set) var notes: [UInt8 : DisjointNotes]
    
    /// The contents are sorted on initialization.
    ///
    /// The contents are not guaranteed to be sorted after iteration, as `container` does not update `contents` when the `onset`s for individual notes change.
    public fileprivate(set) var contents: UnsafeMutableBufferPointer<MIDINote>
    
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
    public init(
        container: MIDIContainer,
        minimumConsecutiveNotesGap: Double = 1/128
    ) {
        self.notes = [:]
        self.contents = .allocate(capacity: 0)
        self.sustains = []
        
        self._init(container: container, minimumConsecutiveNotesGap: minimumConsecutiveNotesGap)
    }
    
    @inlinable
    deinit {
        self.contents.deallocate()
    }
    
}


extension IndexedContainer {
    
    /// - Parameters:
    ///   - container: The source container.
    ///   - minimumConsecutiveNotesGap: The minimum gap between two consecutive notes. The default value is `1/128`. The minimum length of individual note from La campanella in G-Sharp Minor by Lang Lang is 0.013 beat, which is around 1/64 beat.
    ///   - runningLength: The length for calculating the running average. The default value is `4` beats, that is one measure in a 4/4 sheet.
    ///
    /// Any methods that returns a new ``IndexedContainer`` will use the parameters set in the initializer.
    func _init(
        container: MIDIContainer,
        minimumConsecutiveNotesGap: Double = 1/128
    ) {
        var notes: [MIDINote] = []
        let sustains: MIDISustainEvents
        
        if container.tracks.count == 1,
           let track = container.tracks.first {
            notes = track.notes.contents
            
            sustains = track.sustains
        } else {
            notes.reserveCapacity(container.tracks.map(\.notes.count).sum)
            for (trackIndex, track) in container.tracks.enumerated() {
                var index = 0
                while index < track.notes.count {
                    var note = track.notes[index]
                    note.channel = UInt8(trackIndex)
                    notes.append(note)
                    
                    index &+= 1
                }
            }
            sustains = MIDISustainEvents(container.tracks.flatMap(\.sustains))
        }
        
        notes.sort { $0.onset < $1.onset }
        
        // MARK: -  sanitize notes
        do {
            // construct grouped
            var grouped: [UInt8 : [MIDINote]] = [:]
            notes.forEach { _, element in
                grouped[element.note, default: []].append(element)
            }
            
            // construct dictionary
            var index = 0 as UInt8
            while index <= 108 {
                defer { index &+= 1 }
                guard grouped[index] != nil else { continue }
                var i = 0
                while i < grouped[index]!.count - 1 {
                    if grouped[index]![i + 1].onset - grouped[index]![i].onset < minimumConsecutiveNotesGap {
                        let offset = Swift.min(grouped[index]![i].offset, grouped[index]![i + 1].onset - minimumConsecutiveNotesGap)
                        
                        if offset < grouped[index]![i + 1].offset {
                            grouped[index]![i + 1].onset = offset
                        } else {
                            // completely within, remove it
                            grouped[index]!.remove(at: i)
                            continue
                        }
                    } else {
                        // ensures non-overlapping
                        grouped[index]![i].offset = clamp(grouped[index]![i].offset, max: grouped[index]![i + 1].onset - minimumConsecutiveNotesGap)
                        if grouped[index]![i].duration < minimumConsecutiveNotesGap {
                            // note is too short, remove it
                            grouped[index]!.remove(at: i)
                            continue
                        }
                    }
                    
                    i &+= 1
                }
            }
            
            notes = grouped.values.flatten()
            notes.sort { $0.onset < $1.onset }
        }
        
        let contents: UnsafeMutableBufferPointer<MIDINote> = .allocate(capacity: notes.count)
        memcpy(contents.baseAddress!, &notes, MemoryLayout<MIDINote>.stride * notes.count)
        
        self.contents.deallocate()
        self.contents = contents
        self.sustains = sustains
        
        // construct grouped
        var grouped: [UInt8 : [ReferenceNote]] = [:]
        contents.forEach { index, element in
            grouped[element.note, default: []].append(ReferenceNote(contents.baseAddress! + index))
        }
        
        
        // construct dictionary
        var dictionary: [UInt8 : DisjointNotes] = [:]
        var index = 0 as UInt8
        while index <= 108 {
            defer { index &+= 1 }
            guard let contents = grouped[index] else { continue }
            guard !contents.isEmpty else { continue }
            dictionary[index] = DisjointNotes(contents)
        }
        _ = consume grouped
        
        self.notes = dictionary
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

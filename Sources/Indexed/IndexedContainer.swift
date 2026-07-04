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
///
/// An `IndexedContainer` is never sendable, crossing domain could corrupt memory. Sendable `MIDIContainer` instead. However, some operations could be heavy, hence it is recommended to put the entire operation in async.
///
/// - Note: A `IndexedContainer` always use 120BPM and tempo is converted automatically during initialization.
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
    
    public var controlEvents: MIDIControlEvents
    public var metaEvents: [MIDIMetaEvent]
    
    
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
        
        let track = MIDITrack(notes: MIDINotes(consume notes), sustains: self.sustains, metaEvents: metaEvents, controlEvents: self.controlEvents)
        return MIDIContainer(tracks: [track])
    }
    
    /// Creates an indexed representation normalized to 120 BPM.
    ///
    /// Pitches are clamped to `21...108`. For multiple source tracks, track indices wrap across
    /// the 16 MIDI channels. Overlapping or touching sustain events are merged, and when two
    /// same-pitch onsets cannot satisfy `minimumConsecutiveNotesGap`, the later note is retained.
    ///
    /// - Parameters:
    ///   - container: The source container.
    ///   - minimumConsecutiveNotesGap: The strictly positive, finite minimum gap between two consecutive notes. The default value is `1/128`.
    public init(
        container: MIDIContainer,
        minimumConsecutiveNotesGap: Double = 1/128
    ) {
        self.notes = [:]
        self.contents = .allocate(capacity: 0)
        self.sustains = []
        self.controlEvents = []
        self.metaEvents = []
        
        self._init(container: container, minimumConsecutiveNotesGap: minimumConsecutiveNotesGap)
    }
    
    @inlinable
    deinit {
        self.contents.deallocate()
    }
    
}


extension IndexedContainer {
    
    /// Rebuilds this container from a source normalized to the indexed representation's invariants.
    ///
    /// - Parameters:
    ///   - container: The source container.
    ///   - minimumConsecutiveNotesGap: The strictly positive, finite minimum gap between consecutive same-pitch notes.
    ///
    /// - Note: An `IndexedContainer` always uses 120 BPM and converts tempo automatically.
    func _init(
        container: MIDIContainer,
        minimumConsecutiveNotesGap: Double = 1/128
    ) {
        precondition(
            minimumConsecutiveNotesGap.isFinite && minimumConsecutiveNotesGap > 0,
            "minimumConsecutiveNotesGap must be finite and greater than zero"
        )
        
        var copy = container
        copy.normalizeToConstantTempo(120)
        
        var notes: [MIDINote] = []
        notes.reserveCapacity(copy.tracks.map(\.notes.count).sum)
        for (trackIndex, track) in copy.tracks.enumerated() {
            for var note in track.notes {
                note.note = clamp(note.note, min: 21, max: 108)
                if copy.tracks.count > 1 {
                    note.channel = UInt8(trackIndex % 16)
                }
                notes.append(note)
            }
        }
        
        let sortedSustains = copy.tracks.flatMap(\.sustains).sorted()
        var mergedSustains: [MIDISustainEvent] = []
        mergedSustains.reserveCapacity(sortedSustains.count)
        for sustain in sortedSustains {
            guard var previous = mergedSustains.last else {
                mergedSustains.append(sustain)
                continue
            }
            guard sustain.onset <= previous.offset else {
                mergedSustains.append(sustain)
                continue
            }
            previous.offset = Swift.max(previous.offset, sustain.offset)
            mergedSustains[mergedSustains.count - 1] = previous
        }
        let sustains = MIDISustainEvents(consume mergedSustains)
        
        notes.sort { $0.onset < $1.onset }
        
        // MARK: - Sanitize notes
        do {
            var grouped: [UInt8 : [MIDINote]] = [:]
            notes.forEach { _, element in
                grouped[element.note, default: []].append(element)
            }
            
            for pitch in 21...108 as ClosedRange<UInt8> {
                guard grouped[pitch] != nil else { continue }
                var index = 0
                while index < grouped[pitch]!.count - 1 {
                    let nextOnset = grouped[pitch]![index + 1].onset
                    guard nextOnset - grouped[pitch]![index].onset >= minimumConsecutiveNotesGap else {
                        grouped[pitch]!.remove(at: index)
                        continue
                    }
                    
                    grouped[pitch]![index].offset = Swift.min(
                        grouped[pitch]![index].offset,
                        nextOnset - minimumConsecutiveNotesGap
                    )
                    guard grouped[pitch]![index].duration >= minimumConsecutiveNotesGap else {
                        grouped[pitch]!.remove(at: index)
                        continue
                    }
                    
                    index &+= 1
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
        
        self.controlEvents = MIDIControlEvents(container.tracks.flatMap(\.controlEvents))
        self.metaEvents = container.tracks.flatMap(\.metaEvents)
        // tempo track is ignored as IndexedContainer is 120BPM.
        
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

//
//  Track.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import AudioToolbox
import DetailedDescription
import AVFoundation


/// A MIDI Track.
///
/// In CoreAudio, the time stamps are represented in `MusicTimeStamp`, measured in *beats*.
///
/// ## The Time Signature
///
/// The **numerator** indicates the number of *beats* per measure.
///
/// The **denominator** indicates *n*th note gets one *beat*.
///
/// For Example, a `4/4` indicates that there are 4 beats per measure, and each beat is a quarter note
public struct MIDITrack: CustomStringConvertible, CustomDetailedStringConvertible, Sendable, Equatable {
    
    public var notes: Notes
    
    public var sustains: MIDISustainEvents
    
    public var metaEvents: [MetaEvent]
    
    /// The range of the notes in the track.
    public var range: ClosedRange<MusicTimeStamp> {
        let onsets = notes.map(\.onset)
        let offsets = notes.map(\.offset)
        
        return ClosedRange(uncheckedBounds: (onsets.min() ?? 0, offsets.max() ?? 0))
    }
    
    
    internal func makeTrack(sequence: MusicSequence) -> MusicTrack {
        var musicTrack: MusicTrack?
        MusicSequenceNewTrack(sequence, &musicTrack)
        guard let musicTrack else {
            fatalError()
        }
        
        for metaEvent in metaEvents {
            _ = metaEvent.withUnsafePointer { pointer in
                MusicTrackNewMetaEvent(musicTrack, metaEvent.timestamp, pointer)
            }
        }
        
        for note in notes {
            var message = MIDINoteMessage(channel: note.channel, note: note.note, velocity: note.velocity, releaseVelocity: note.releaseVelocity, duration: Float32(note.offset - note.onset))
            MusicTrackNewMIDINoteEvent(musicTrack, note.onset, &message)
        }
        
        for sustain in sustains {
            var first = MIDIChannelMessage(status: 0xB0, data1: 64, data2: 127, reserved: 0)
            var last  = MIDIChannelMessage(status: 0xB0, data1: 64, data2: 0,   reserved: 0)
            MusicTrackNewMIDIChannelEvent(musicTrack, sustain.onset, &first)
            MusicTrackNewMIDIChannelEvent(musicTrack, sustain.offset, &last)
        }
        
        return musicTrack
    }
    
    @inlinable
    public mutating func appendNotes(from rhs: MIDITrack) {
        self.notes.append(contentsOf: rhs.notes)
    }
    
    /// Quantize the track.
    ///
    /// In a time signature of 4/4, A `beats` of 1 indicates a quarter note (one beat), regardless of time signature.
    ///
    /// - SeeAlso: ``MIDITrack``
    public mutating func quantize(by beats: MusicTimeStamp) {
        func _quantize(value: inout MusicTimeStamp) {
            value = (value / beats).rounded(.toNearestOrAwayFromZero) * beats
        }
        
        for i in 0..<self.notes.count {
            var duration = self.notes[i].duration
            _quantize(value: &duration) // duration then onset, as onset would change the duration.
            _quantize(value: &self.notes[i].onset)
            self.notes[i].duration = Swift.max(duration, 1/4)
        }
        
        for i in 0..<self.sustains.count {
            _quantize(value: &self.sustains[i].onset)
            _quantize(value: &self.sustains[i].offset)
        }
    }
    
    /// Returns the measures of the track.
    ///
    /// The measures are well-defined in MIDI. In a time signature of `n/m`, `n` `m`th notes go in one measure.
    ///
    /// The notes cannot be split in half. The measures record only the `onset`, ignoring the `offset`
    ///
    /// - Returns: The raw measures.
    public func measures(timeSignature: (Int, Int)) -> [MIDIMeasure] {
        let length = Double(timeSignature.0)
        
        func groupings<T>(_ elements: [T], upperBound: Double, feature: (T) -> MusicTimeStamp) -> [[T]] {
            
            var groups: [[T]] = []
            var current: [T] = []
            
            var lowerBound: Double = 0
            let elements = elements.sorted(by: { feature($0) < feature($1) })
            
            var index = 0
            while lowerBound < upperBound {
                var next: T? {
                    guard index < elements.count else { return nil }
                    return elements[index]
                }
                
                while let next,
                      feature(next) < lowerBound + length {
                    current.append(next)
                    index += 1
                }
                
                groups.append(current)
                current = []
                lowerBound += length
            }
            
            groups.append(current)
            
            assert(groups.count == Int(upperBound / length) + 2)
            
            return groups
        }
        
        guard !self.notes.isEmpty else { return [] }
        
        let upperBound = self.notes.map(\.offset).max()!
        let sustains = groupings(self.sustains.contents, upperBound: upperBound, feature: \.onset)
        let notes = groupings(self.notes.contents, upperBound: upperBound, feature: \.onset)
        
        assert(notes.count == sustains.count)
        
        return zip(notes, sustains).map({ MIDIMeasure(notes: MIDINotes($0.0), sustains: MIDISustainEvents($0.1)) })
    }
    
    /// Returns the **inferred** measures of the track.
    public func inferredMeasures() -> [MIDIMeasure] {
        fatalError()
    }
    
    
    public init(notes: [Note] = [], sustains: [SustainEvent] = [], metaEvents: [MetaEvent] = []) {
        self.notes = Notes(notes)
        self.sustains = MIDISustainEvents(sustains)
        self.metaEvents = metaEvents
    }
    
    public init(notes: Notes, sustains: MIDISustainEvents, metaEvents: [MetaEvent] = []) {
        self.notes = notes
        self.sustains = sustains
        self.metaEvents = metaEvents
    }
    
    public typealias Note = MIDINote
                       
    public typealias Notes = MIDINotes
    
    public typealias SustainEvent = MIDISustainEvent
    
    public typealias MetaEvent = MIDIMetaEvent
    
    
    public var description: String {
        self.detailedDescription
    }
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDITrack>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.notes)
            descriptor.sequence(for: \.sustains)
            descriptor.sequence(for: \.metaEvents)
        }
    }
    
}


public extension Array<MIDITrack> {
    
    mutating func forEach(body: (_ index: Index, _ element: inout Element) -> Void) {
        var i = 0
        while i < self.endIndex {
            body(i, &self[i])
            
            i &+= 1
        }
    }
    
}

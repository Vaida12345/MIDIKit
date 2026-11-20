//
//  Track.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Essentials
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
public struct MIDITrack: CustomStringConvertible, DetailedStringConvertible, Sendable, Equatable {
    
    public var notes: Notes
    
    public var sustains: MIDISustainEvents
    
    public var metaEvents: [MetaEvent]
    
    public var rawData: [MIDIRawData]
    
    public var channelEvents: MIDIChannelEvents
    
    /// The time span of the notes in the track, from the earliest onset to the latest offset, or `nil` if the track has no notes.
    @inlinable
    public var range: ClosedRange<MusicTimeStamp>? {
        guard let onset = notes.min(of: \.onset), let offset = notes.max(of: \.offset) else { return nil }
        return onset ... Swift.max(onset, offset)
    }
    
    @inlinable
    public mutating func appendNotes(from rhs: MIDITrack) {
        self.notes.append(contentsOf: rhs.notes)
    }
    
    @inlinable
    public init(notes: [Note] = [], sustains: [SustainEvent] = [], metaEvents: [MetaEvent] = [], channelEvents: MIDIChannelEvents = []) {
        self.notes = Notes(notes)
        self.sustains = MIDISustainEvents(sustains)
        self.metaEvents = metaEvents
        self.rawData = []
        self.channelEvents = channelEvents
    }
    
    @inlinable
    public init(notes: [Note], sustains: MIDISustainEvents, metaEvents: [MetaEvent] = [], channelEvents: MIDIChannelEvents = []) {
        self.notes = Notes(notes)
        self.sustains = sustains
        self.metaEvents = metaEvents
        self.rawData = []
        self.channelEvents = channelEvents
    }
    
    @inlinable
    public init(notes: Notes, sustains: MIDISustainEvents, metaEvents: [MetaEvent] = [], channelEvents: MIDIChannelEvents = []) {
        self.notes = notes
        self.sustains = sustains
        self.metaEvents = metaEvents
        self.rawData = []
        self.channelEvents = channelEvents
    }
    
    public typealias Note = MIDINote
                       
    public typealias Notes = MIDINotes
    
    public typealias SustainEvent = MIDISustainEvent
    
    public typealias MetaEvent = MIDIMetaEvent
    
    
    @inlinable
    public var description: String {
        self.detailedDescription
    }
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDITrack>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.notes)
            descriptor.sequence(for: \.sustains)
            descriptor.sequence(for: \.metaEvents)
            descriptor.sequence(for: \.rawData)
        }
    }
    
}

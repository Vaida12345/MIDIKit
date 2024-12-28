//
//  MIDITempoTrack.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import AudioToolbox
import DetailedDescription
import AVFoundation


public struct MIDITempoTrack: Sendable, CustomStringConvertible, CustomDetailedStringConvertible, Equatable, ArrayRepresentable {
    
    public var events: [MIDIMetaEvent]
    
    public var contents: [Tempo]
    
    
    public mutating func setTimeSignature(beatsPerMeasure: UInt8, beatsPerNote: UInt8) {
        var data = Data(capacity: 4)
        data.append(beatsPerMeasure)
        data.append(UInt8(log2(Double(beatsPerNote))))
        data.append(24)
        data.append(8)
        
        if let eventIndex = events.firstIndex(where: { AVMIDIMetaEvent.EventType(rawValue: Int($0.type)) == .timeSignature }) {
            events[eventIndex].data = data
        } else {
            events.append(MIDITrack.MetaEvent(timestamp: 0, type: UInt8(AVMIDIMetaEvent.EventType.timeSignature.rawValue), data: data))
        }
    }
    
    public init(events: [MIDITrack.MetaEvent], tempos: [Tempo]) {
        self.events = events
        self.contents = tempos
    }
    
    public init(_ contents: [Element]) {
        self.init(events: [], tempos: contents)
    }
    
    
    public var description: String {
        self.detailedDescription
    }
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDITempoTrack>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.contents)
            descriptor.sequence(for: \.events)
        }
    }
    
    public typealias Element = Tempo
    
    public struct Tempo: Sendable, Equatable {
        
        public var timestamp: MusicTimeStamp
        
        public var tempo: Double
        
        public init(timestamp: MusicTimeStamp, tempo: Double) {
            self.timestamp = timestamp
            self.tempo = tempo
        }
    }
    
}

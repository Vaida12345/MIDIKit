//
//  MIDITempoTrack.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import AudioToolbox
import DetailedDescription


public struct MIDITempoTrack: Sendable, CustomStringConvertible, CustomDetailedStringConvertible, Equatable {
    
    public var events: [MIDITrack.MetaEvent]
    
    public var tempos: [Tempo]
    
    
    public init(events: [MIDITrack.MetaEvent], tempos: [Tempo]) {
        self.events = events
        self.tempos = tempos
    }
    
    
    public var description: String {
        self.detailedDescription
    }
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDITempoTrack>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.tempos)
            descriptor.sequence(for: \.events)
        }
    }
    
    public struct Tempo: Sendable, Equatable {
        
        public let timestamp: MusicTimeStamp
        
        public let tempo: Double
        
    }
    
}

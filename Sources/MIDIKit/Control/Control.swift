//
//  Control.swift
//  MIDIKit
//
//  Created by Vaida on 8/26/24.
//

import AudioToolbox


public struct MIDIControlEvent: Sendable, Equatable, Hashable {
    
    public var onset: MusicTimeStamp
    
    public var channel: UInt8
    
    public var velocity: UInt8
    
    
    @inlinable
    public init(onset: MusicTimeStamp, channel: UInt8, velocity: UInt8) {
        self.onset = onset
        self.channel = channel
        self.velocity = velocity
    }
    
}


@available(macOS 12.0, *)
extension MIDIControlEvent: CustomStringConvertible {
    
    public var description: String {
        "Control(\(onset.formatted(.number.precision(.fractionLength(2)))), channel: \(self.channel), velocity: \(self.velocity))"
    }
    
}

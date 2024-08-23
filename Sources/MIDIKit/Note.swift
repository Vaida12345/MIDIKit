//
//  Note.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import AudioToolbox


public struct MIDINote: Sendable {
    
    public var onset: MusicTimeStamp
    public var offset: MusicTimeStamp
    public var note: UInt8
    public var velocity: UInt8
    public var channel: UInt8
    public var releaseVelocity: UInt8
    
    public var length: Double {
        self.offset - self.onset
    }
    
    public init(onset: MusicTimeStamp, offset: MusicTimeStamp, note: UInt8, velocity: UInt8, channel: UInt8, releaseVelocity: UInt8 = 0) {
        self.onset = onset
        self.offset = offset
        self.note = note
        self.velocity = velocity
        self.channel = channel
        self.releaseVelocity = releaseVelocity
    }
    
    internal init(onset: Double, message: MIDINoteMessage) {
        self.onset = onset
        
        self.offset = self.onset + Double(message.duration)
        self.note = message.note
        self.velocity = message.velocity
        self.channel = message.channel
        self.releaseVelocity = message.releaseVelocity
    }
    
}


@available(macOS 12.0, *)
extension MIDINote: CustomStringConvertible {
    
    public var description: String {
        var value = "Note(range: \(onset.formatted(.number.precision(.fractionLength(2)))) - \(offset.formatted(.number.precision(.fractionLength(2)))), note: \(self.note), velocity: \(self.velocity)"
        if self.channel != 0 {
            value += ", channel: \(self.channel)"
        }
        if self.releaseVelocity != 0 {
            value += ", release: \(self.releaseVelocity)"
        }
        
        return value + ")"
    }
    
}

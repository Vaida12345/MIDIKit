//
//  MIDINote.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Foundation
import AudioToolbox


public final class ReferenceNote: Equatable, Interval, Hashable {
    
    @inlinable
    public var content: MIDINote {
        MIDINote(onset: onset, offset: offset, note: note, velocity: velocity, channel: channel, releaseVelocity: releaseVelocity)
    }
    
    /// The onset, in beats.
    public var onset: MusicTimeStamp
    public var offset: MusicTimeStamp
    /// The key
    public var note: UInt8
    public var velocity: UInt8
    public var channel: UInt8
    public var releaseVelocity: UInt8
    /// The duration of the note, on set, it changes the ``offset``, while ``onset`` remains the same.
    @inlinable
    public var duration: Double {
        get {
            self.offset - self.onset
        }
        set {
            self.offset = self.onset + newValue
        }
    }
    
    @inlinable
    public init(note: MIDINote) {
        self.onset = note.onset
        self.offset = note.offset
        self.note = note.note
        self.velocity = note.velocity
        self.channel = note.channel
        self.releaseVelocity = note.releaseVelocity
    }
    
    @inlinable
    public static func == (lhs: ReferenceNote, rhs: ReferenceNote) -> Bool {
        lhs.onset == rhs.onset &&
        lhs.offset == rhs.offset &&
        lhs.note == rhs.note &&
        lhs.velocity == rhs.velocity &&
        lhs.channel == rhs.channel &&
        lhs.releaseVelocity == rhs.releaseVelocity
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.onset)
        hasher.combine(self.offset)
        hasher.combine(self.note)
        hasher.combine(self.velocity)
        hasher.combine(self.channel)
        hasher.combine(self.releaseVelocity)
    }
    
}

extension ReferenceNote: CustomStringConvertible {
    
    @inlinable
    public var description: String {
        self.content.description
    }
    
}

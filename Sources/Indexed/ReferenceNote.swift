//
//  MIDINote.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Foundation
import AudioToolbox


public final class ReferenceNote: Equatable, Interval {
    
    public var content: MIDINote
    
    /// The onset, in beats.
    @inlinable
    public var onset: MusicTimeStamp {
        get { content.onset }
        set { content.onset = newValue }
    }
    @inlinable
    public var offset: MusicTimeStamp {
        get { content.offset }
        set { content.offset = newValue }
    }
    /// The key
    @inlinable
    public var note: UInt8 {
        get { content.note }
        set { content.note = newValue }
    }
    @inlinable
    public var velocity: UInt8 {
        get { content.velocity }
        set { content.velocity = newValue }
    }
    @inlinable
    public var channel: UInt8 {
        get { content.channel }
        set { content.channel = newValue }
    }
    @inlinable
    public var releaseVelocity: UInt8 {
        get { content.releaseVelocity }
        set { content.releaseVelocity = newValue }
    }
    /// The duration of the note, on set, it changes the ``offset``, while ``onset`` remains the same.
    @inlinable
    public var duration: Double {
        get { content.duration }
        set { content.duration = newValue }
    }
    
    public init(note: MIDINote) {
        self.content = note
    }
    
    public static func == (lhs: ReferenceNote, rhs: ReferenceNote) -> Bool {
        lhs.content == rhs.content
    }
    
}

extension ReferenceNote: CustomStringConvertible {
    
    public var description: String {
        self.content.description
    }
    
}

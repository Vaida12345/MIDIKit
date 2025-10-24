//
//  MIDINote.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Foundation
import AudioToolbox


public struct ReferenceNote: Hashable {
    
    let pointer: UnsafeMutablePointer<MIDINote>
    
    /// Internal temporary value associated with a note.
    var store: UInt = 0
    
    public var pointee: MIDINote {
        get { self.pointer.pointee }
        nonmutating set { self.pointer.pointee = newValue }
    }
    
    init(_ pointer: UnsafeMutablePointer<MIDINote>) {
        self.pointer = pointer
    }
    
}


extension ReferenceNote: CustomStringConvertible {
    
    @inlinable
    public var description: String {
        self.pointee.description
    }
    
}

extension ReferenceNote: Interval {
    
    @inlinable
    public var onset: Double { self.pointee.onset }
    
    @inlinable
    public var offset: Double {
        get {
            self.pointee.offset
        }
        nonmutating set {
            self.pointee.offset = newValue
        }
    }
    
    @inlinable
    public var duration: Double {
        get {
            self.pointee.duration
        }
        nonmutating set {
            self.pointee.duration = newValue
        }
    }
    
    @inlinable
    public var note: UInt8 {
        get { self.pointee.note }
        nonmutating set { self.pointee.note = newValue }
    }
    
    /// The key, alias to `note`.
    @inlinable
    public var pitch: UInt8 {
        get { self.note }
        nonmutating set { self.note = newValue }
    }
    
    @inlinable
    public var velocity: UInt8 {
        get {
            self.pointee.velocity
        }
        nonmutating set {
            self.pointee.velocity = newValue
        }
    }
    
    @inlinable
    public var channel: UInt8 {
        get {
            self.pointee.channel
        }
        nonmutating set {
            self.pointee.channel = newValue
        }
    }
    
    @inlinable
    public var releaseVelocity: UInt8 { self.pointee.releaseVelocity }
    
}

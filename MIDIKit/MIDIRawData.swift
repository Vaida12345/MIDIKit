//
//  MIDIRawData.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-23.
//

import Foundation
import AudioToolbox


/// A raw MIDI message, such as a system exclusive (SysEx) message, read from or written to a track.
public struct MIDIRawData: Sendable, Equatable {
    
    public var timestamp: MusicTimeStamp
    
    public var data: Data
    
    
    @inlinable
    public init(timestamp: MusicTimeStamp, data: Data) {
        self.timestamp = timestamp
        self.data = data
    }
    
    /// Calls `body` with a pointer to an `AudioToolbox.MIDIRawData` that holds this message.
    ///
    /// In C, `MIDIRawData` is `{ UInt32 length; UInt8 data[1]; }`, where `data` runs past the end of the struct for `length` bytes. Swift imports `data` as a single byte, so a Swift `MIDIRawData` value cannot hold a longer message, and writing past it would be undefined behavior.
    ///
    /// Instead, this allocates raw memory for the length and all the bytes, writes them as raw bytes, and binds only the start of the buffer to `MIDIRawData`. Swift never reads the trailing bytes through a Swift type; Core Audio, which is C, reads `length` bytes, as the flexible array member is meant to be used.
    func withUnsafePointer<T>(body: (UnsafePointer<AudioToolbox.MIDIRawData>) throws -> T) rethrows -> T {
        try withFlexibleBuffer(header: { $0.storeBytes(of: UInt32(self.data.count), as: UInt32.self) }, headerSize: 4, data: self.data, as: AudioToolbox.MIDIRawData.self, body: body)
    }
    
}


@available(macOS 13.0, *)
extension MIDIRawData: CustomStringConvertible {
    
    public var description: String {
        String(data: self.data, encoding: .utf8).map { "\"" + $0 + "\"" } ?? data.description
    }
    
}


/// Calls `body` with a pointer to a C struct whose last member is a flexible array, filled with `header` followed by `data`.
///
/// The buffer is allocated as raw memory aligned for `T`, at least `MemoryLayout<T>.size` bytes long, and only its start is bound to `T`. The bytes past the struct are written and read as raw memory only, by Core Audio.
func withFlexibleBuffer<T, Result>(header: (UnsafeMutableRawPointer) -> Void, headerSize: Int, data: Data, as type: T.Type, body: (UnsafePointer<T>) throws -> Result) rethrows -> Result {
    let byteCount = Swift.max(headerSize + data.count, MemoryLayout<T>.size)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<T>.alignment)
    defer { buffer.deallocate() }
    buffer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    header(buffer)
    data.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return }
        (buffer + headerSize).copyMemory(from: base, byteCount: bytes.count)
    }
    return try body(UnsafePointer(buffer.bindMemory(to: T.self, capacity: 1)))
}

//
//  Container + IO.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import AudioToolbox
import FinderItem


extension MIDIContainer {
    
    /// The resolution of written MIDI files, in ticks per quarter note: 9,600.
    ///
    /// Every time is rounded to this grid when a file is written, so a time is off by at most half a tick, 1/19,200 beat, about 26 µs at 120 BPM. Times already on a grid that divides 9,600 are written exactly.
    ///
    /// The value is chosen so that common files round-trip without any rounding:
    ///
    /// - It is twice 4,800, the resolution MIDIKit used before, so every time a file written at 4,800 holds is still a whole number of ticks.
    /// - It is a multiple of the resolutions most software writes: 96 (Ableton Live), 384 (Disklavier recordings, such as the MAESTRO and ASAP datasets, and PianoTranscription), 480 (MuseScore, and Logic exports), and 960 (Reaper, Cakewalk, Sibelius), as well as 120, 192, 240, and 1,920. 4,800 is not a multiple of 384.
    /// - It is 2⁷ × 3 × 5², so 128th notes, triplets, quintuplets, and quintuplets within quintuplets fall on whole ticks.
    /// - It stays well below the 32,767 the file format allows. Common files use 96 to 960 ticks, and some software converts files to its own grid, so the resolution is kept no larger than it needs to be: 9,600 is the smallest value that adds 384 to the 4,800 grid.
    public static let writeResolution: Int16 = 9600

    /// Writes the MIDI as file to `destination`.
    ///
    /// File write is atomic. Times are rounded to the grid of ``writeResolution``, as described in ``data()``.
    @inlinable
    public func write(to destination: FinderItem) throws {
        try self.data().write(to: destination, options: .atomic)
    }
    
    /// Returns the container as the data of a standard MIDI file.
    ///
    /// The file has a resolution of ``writeResolution``, 9,600 ticks per quarter note. Every time is rounded to the nearest tick, so it moves by at most half a tick, and the error never accumulates along the file. Every note and sustain lasts at least one tick, so a note shorter than a tick is lengthened rather than lost. Note durations are stored as `Float32`, which keeps them exact to the tick for notes up to about 870 beats long.
    @inlinable
    public func data() throws -> Data {
#if DEBUG
        self._checkConsistency()
#endif
        
        let sequence = try self.makeSequence(resolution: MIDIContainer.writeResolution)
        defer { DisposeMusicSequence(sequence) }
        
        var data: Unmanaged<CFData>?
        try withErrorCaptured {
            MusicSequenceFileCreateData(sequence, .midiType, [], MIDIContainer.writeResolution, &data)
        }
        return data!.takeRetainedValue() as Data
    }
    
    @inlinable
    public init(at source: FinderItem) throws {
        guard source.exists else { throw FinderItem.FileError(.noSuchFile, source: source, intent: .reading) }
        
        var sequence: MusicSequence!
        try withErrorCaptured {
            NewMusicSequence(&sequence)
        }
        defer { DisposeMusicSequence(sequence) }
        
        try withErrorCaptured {
            MusicSequenceFileLoad(sequence, source.url as CFURL, .midiType, .smf_PreserveTracks)
        }
        
        try self.init(sequence: sequence)
    }
    
    @inlinable
    public init(data: Data) throws {
        var sequence: MusicSequence!
        try withErrorCaptured {
            NewMusicSequence(&sequence)
        }
        defer { DisposeMusicSequence(sequence) }
        
        try withErrorCaptured {
            MusicSequenceFileLoadData(sequence, data as CFData, .midiType, .smf_PreserveTracks)
        }
        
        try self.init(sequence: sequence)
    }
    
}

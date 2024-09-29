//
//  Container.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import System
import AudioToolbox
import DetailedDescription
import FinderItem


public struct MIDIContainer: CustomStringConvertible, CustomDetailedStringConvertible, Sendable, Equatable {
    
    public var tracks: [MIDITrack]
    
    public var tempo: MIDITempoTrack
    
    
    public func makeSequence() -> MusicSequence {
        var sequence: MusicSequence?
        NewMusicSequence(&sequence)
        guard let sequence else {
            fatalError()
        }
        
        var tempoTrack: MusicTrack?
        MusicSequenceGetTempoTrack(sequence, &tempoTrack)
        guard let tempoTrack else {
            fatalError()
        }
        for event in tempo.events {
            _ = event.withUnsafePointer { pointer in
                MusicTrackNewMetaEvent(tempoTrack, event.timestamp, pointer)
            }
        }
        for tempo in tempo.tempos {
            MusicTrackNewExtendedTempoEvent(tempoTrack, tempo.timestamp, tempo.tempo)
        }
        
        for track in tracks {
            _ = track.makeTrack(sequence: sequence)
        }
        
        return sequence
    }
    
    public func writeData(to destination: FinderItem) throws {
        try destination.removeIfExists()
        let code = MusicSequenceFileCreate(self.makeSequence(), destination.url as CFURL, .midiType, .eraseFile, .max)
        guard code == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
    }
    
    public func data() throws -> Data {
        var data: Unmanaged<CFData>?
        let code = MusicSequenceFileCreateData(self.makeSequence(), .midiType, .eraseFile, 0, &data)
        guard code == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
        return data!.takeRetainedValue() as Data
    }
    
    public init(tracks: [MIDITrack] = [], tempo: MIDITempoTrack = MIDITempoTrack(events: [], tempos: [])) {
        self.tracks = tracks
        self.tempo = tempo
    }
    
    public init(sequence: MusicSequence) throws {
        defer {
            DisposeMusicSequence(sequence)
        }
        
        let _count = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        defer { _count.deallocate() }
        let _count_code = MusicSequenceGetTrackCount(sequence, _count)
        guard _count_code == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(_count_code)) }
        let count = _count.pointee
        
        var midiTracks: [MIDITrack] = []
        
        struct AdditionalInfo {
            var tempos: [MIDITempoTrack.Tempo]
        }
        
        func processTrack(track: MusicTrack, additionalInfo: inout AdditionalInfo) -> MIDITrack? {
            var midiTrack = MIDITrack()
            
            var iterator: MusicEventIterator?
            NewMusicEventIterator(track, &iterator)
            
            guard let iterator else { return nil }
            defer {
                DisposeMusicEventIterator(iterator)
            }
            
            var iteratorHasNextEvent: Bool {
                var bool = DarwinBoolean(false)
                MusicEventIteratorHasCurrentEvent(iterator, &bool)
                return bool.boolValue
            }
            
            var sustainOpen: Bool = false
            var sustainStart: MusicTimeStamp = 0
            var sustains: [MIDISustainEvent] = []
            
            while iteratorHasNextEvent {
                var dataPointer: UnsafeRawPointer?
                var dataSize: UInt32 = 0
                var timeStamp: MusicTimeStamp = 0
                var eventType: MusicEventType = kMusicEventType_NULL
                
                MusicEventIteratorGetEventInfo(iterator, &timeStamp, &eventType, &dataPointer, &dataSize)
                
                if let dataPointer {
                    
                    // The raw values, 0-10
                    // kMusicEventType_NULL
                    // kMusicEventType_ExtendedNote
                    // ???
                    // kMusicEventType_ExtendedTempo
                    // kMusicEventType_User
                    // kMusicEventType_Meta
                    // kMusicEventType_MIDINoteMessage
                    // kMusicEventType_MIDIChannelMessage
                    // kMusicEventType_MIDIRawData
                    // kMusicEventType_Parameter
                    // kMusicEventType_AUPreset
                    
                    switch eventType {
                    case kMusicEventType_MIDINoteMessage:
                        let event = dataPointer.bindMemory(to: MIDINoteMessage.self, capacity: 1).pointee
                        midiTrack.notes.append(MIDITrack.Note(onset: timeStamp, message: event))
                        
                    case kMusicEventType_MIDIChannelMessage:
                        let event = dataPointer.bindMemory(to: MIDIChannelMessage.self, capacity: 1).pointee
                        if event.status == 0xB0 && event.data1 == 64 {
                            if event.data2 == 127 {
                                sustainOpen = true
                                sustainStart = timeStamp
                            } else {
                                if sustainOpen {
                                    sustains.append(MIDITrack.SustainEvent(onset: sustainStart, offset: timeStamp))
                                }
                            }
                        }
                        
                    case kMusicEventType_Meta:
                        let event = dataPointer.bindMemory(to: AudioToolbox.MIDIMetaEvent.self, capacity: 1).pointee
                        let data = Data(bytes: dataPointer + 8, count: Int(event.dataLength))
                        
                        midiTrack.metaEvents.append(.init(timestamp: timeStamp, type: event.metaEventType, data: data))
                        
                    case kMusicEventType_ExtendedTempo:
                        let tempo = dataPointer.load(as: Double.self)
                        additionalInfo.tempos.append(MIDITempoTrack.Tempo(timestamp: timeStamp, tempo: tempo))
                        
                    default:
                        fatalError("Unhandled event: \(eventType)")
                    }
                }
                
                MusicEventIteratorNextEvent(iterator)
            }
            midiTrack.sustains = MIDISustainEvents(sustains: sustains)
            
            return midiTrack
        }
        
        for i in 0..<count {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, i, &track)
            guard let track else { continue }
            
            var additionInfo = AdditionalInfo(tempos: [])
            guard let midiTrack = processTrack(track: track, additionalInfo: &additionInfo) else { continue }
            midiTracks.append(midiTrack)
        }
        
        var tempoTrack: MusicTrack?
        MusicSequenceGetTempoTrack(sequence, &tempoTrack)
        var additionInfo = AdditionalInfo(tempos: [])
        let midiTempoTrack = processTrack(track: tempoTrack!, additionalInfo: &additionInfo)
        
        self.init(tracks: midiTracks, tempo: .init(events: midiTempoTrack!.metaEvents, tempos: additionInfo.tempos))
    }
    
    public init(at source: FinderItem) throws {
        var sequence: MusicSequence?
        NewMusicSequence(&sequence)
        
        guard let sequence else {
            fatalError()
        }
        
        let code = MusicSequenceFileLoad(sequence, source.url as CFURL, .midiType, .smf_PreserveTracks)
        guard code == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
        
        try self.init(sequence: sequence)
    }
    
    
    public var description: String {
        self.detailedDescription
    }
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDIContainer>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.tracks)
            descriptor.value(for: \.tempo)
        }
    }
    
}


public extension MIDIContainer {
    
    /// Apply the tempo.
    ///
    /// ```swift
    /// // start by normalizing tempo
    /// let referenceNoteLength = container.tracks[0].notes.deriveReferenceNoteLength()
    ///
    /// let tempo = 120 * 1/4 / referenceNoteLength
    /// container.applyTempo(tempo: tempo)
    /// ```
    public mutating func applyTempo(tempo: Double) {
        precondition(self.tempo.tempos.isEmpty || (self.tempo.tempos.count == 1 && self.tempo.tempos[0] == .init(timestamp: 0, tempo: 120)))
        
        if self.tempo.tempos.isEmpty {
            self.tempo.tempos.append(MIDITempoTrack.Tempo(timestamp: 0, tempo: tempo))
        } else {
            self.tempo.tempos[0].tempo = tempo
        }
        
        let factor = tempo / 120
        
        self.tracks.forEach { index, element in
            element.notes.forEach { index, element in
                element.onset *= factor
                element.offset *= factor
            }
            
            element.sustains.forEach { index, element in
                element.onset *= factor
                element.offset *= factor
            }
            
            element.metaEvents.forEach { index, element in
                element.timestamp *= factor
            }
        }
    }
    
    mutating func adjustMIDINotesToConstantTempo(_ constantTempo: Double) {
        // Function to calculate time scaled to the constant tempo
        func scaledTime(at timestamp: MusicTimeStamp, tempoEvents: [MIDITempoTrack.Tempo], constantTempo: Double) -> MusicTimeStamp {
            var lastTempoChangeTime: MusicTimeStamp = 0
            var lastTempo: Double = tempoEvents.first?.tempo ?? constantTempo
            var scaledTime: MusicTimeStamp = 0
            
            for tempoEvent in tempoEvents {
                if timestamp < tempoEvent.timestamp {
                    break
                }
                
                let timeDifference = tempoEvent.timestamp - lastTempoChangeTime
                let scaledTimeSegment = timeDifference * constantTempo / lastTempo
                scaledTime += scaledTimeSegment
                
                lastTempoChangeTime = tempoEvent.timestamp
                lastTempo = tempoEvent.tempo
            }
            
            // Scale remaining time up to the note's timestamp
            let remainingTime = timestamp - lastTempoChangeTime
            scaledTime += remainingTime * constantTempo / lastTempo
            
            return scaledTime
        }
        
        
        self.tracks.forEach { index, track in
            track.notes.forEach { _, note in
                note.onset = scaledTime(at: note.onset, tempoEvents: self.tempo.tempos, constantTempo: constantTempo)
                note.offset = scaledTime(at: note.offset, tempoEvents: self.tempo.tempos, constantTempo: constantTempo)
            }
            
            track.sustains.forEach { _, sustain in
                sustain.onset = scaledTime(at: sustain.onset, tempoEvents: self.tempo.tempos, constantTempo: constantTempo)
                sustain.offset = scaledTime(at: sustain.offset, tempoEvents: self.tempo.tempos, constantTempo: constantTempo)
            }
        }
        
        self.tempo.tempos = [MIDITempoTrack.Tempo(timestamp: 0, tempo: constantTempo)]
    }
    
    /// - Parameters:
    ///   - tempos: The timestamps are defined in *currentTempo*. Such values will be scaled in the results.
    mutating func adjustMIDINotesToVariadicTempo(_ tempos: [MIDITempoTrack.Tempo], currentTempo: Double) {
        guard !tempos.isEmpty else { return }
        
         // *= newTempo / originalTempo
        
        var tempos = tempos
        tempos[0] = MIDITempoTrack.Tempo(timestamp: 0, tempo: tempos[0].tempo)
        
        // Function to calculate time scaled to the variadic tempo
        func scaledTime(at timestamp: MusicTimeStamp, tempoEvents: [MIDITempoTrack.Tempo], constantTempo: Double) -> MusicTimeStamp {
            
            var scaled: Double = 0
            var tempoIterator = tempoEvents.sorted(on: \.timestamp, by: <).makeIterator()
            var currentTempo = tempoIterator.next()! // with the guard, this will never be `nil`.
            
            while let nextTempo = tempoIterator.next() {
                if timestamp < nextTempo.timestamp { break }
                
                let duration = nextTempo.timestamp - currentTempo.timestamp
                scaled += duration * (currentTempo.tempo / constantTempo)
                
                currentTempo = nextTempo
            }
            
            let duration = timestamp - currentTempo.timestamp
            scaled += duration * (currentTempo.tempo / constantTempo)
            
            return scaled
        }
        
        self.tracks.forEach { index, track in
            track.notes.forEach { _, note in
                note.onset = scaledTime(at: note.onset, tempoEvents: tempos, constantTempo: currentTempo)
                note.offset = scaledTime(at: note.offset, tempoEvents: tempos, constantTempo: currentTempo)
            }
            
            track.sustains.forEach { _, sustain in
                sustain.onset = scaledTime(at: sustain.onset, tempoEvents: tempos, constantTempo: currentTempo)
                sustain.offset = scaledTime(at: sustain.offset, tempoEvents: tempos, constantTempo: currentTempo)
            }
        }
        
        self.tempo.tempos = tempos.map {
            MIDITempoTrack.Tempo(timestamp: scaledTime(at: $0.timestamp, tempoEvents: tempos, constantTempo: currentTempo), tempo: $0.tempo)
        }
    }
    
}

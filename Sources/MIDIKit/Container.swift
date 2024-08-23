//
//  Container.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import AudioToolbox
import DetailedDescription


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
    
    public func writeData(to destination: URL) throws {
        let code = MusicSequenceFileCreate(self.makeSequence(), destination as CFURL, .midiType, .eraseFile, 0)
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
                            } else if event.data2 == 0 {
                                assert(sustainOpen)
                                midiTrack.sustains.append(MIDITrack.SustainEvent(onset: sustainStart, offset: timeStamp))
                            } else {
                                fatalError()
                            }
                        }
                        
                    case kMusicEventType_Meta:
                        let event = dataPointer.bindMemory(to: MIDIMetaEvent.self, capacity: 1).pointee
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
    
    public init(at url: URL) throws {
        var sequence: MusicSequence?
        NewMusicSequence(&sequence)
        
        guard let sequence else {
            fatalError()
        }
        
        let code = MusicSequenceFileLoad(sequence, url as CFURL, .midiType, .smf_PreserveTracks)
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

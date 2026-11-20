//
//  MIDITempoTrack.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import AudioToolbox
import DetailedDescription
import AVFoundation


/// The tempo track of a MIDI file: its tempo changes, and the meta events it holds, such as the time and key signatures of format-1 files.
public struct MIDITempoTrack: Sendable, CustomStringConvertible, DetailedStringConvertible, Equatable {

    /// The meta events of the tempo track, such as time and key signatures.
    public var metaEvents: [MIDIMetaEvent]

    /// The tempo changes.
    public var tempos: [Tempo]


    /// The time signature of the track: the first valid time-signature meta event in ``metaEvents``.
    ///
    /// Setting a time signature replaces the data of the first time-signature event, or adds one at time 0 if there is none. Setting `nil` removes every time-signature event.
    ///
    /// A file written without a time signature gets ``MIDITimeSignature/default``, 4/4, from CoreMIDI.
    public var timeSignature: MIDITimeSignature? {
        get {
            var index = 0
            while index < self.metaEvents.count {
                if let signature = MIDITimeSignature(self.metaEvents[index]) { return signature }
                index &+= 1
            }
            return nil
        }
        set {
            guard let newValue else {
                self.metaEvents.removeAll { $0.type == 0x58 }
                return
            }
            if let index = self.metaEvents.firstIndex(where: { $0.type == 0x58 }) {
                self.metaEvents[index].data = newValue.data
            } else {
                self.metaEvents.append(newValue.event(at: 0))
            }
        }
    }

    /// Creates a tempo track.
    ///
    /// Without a time signature, a file is written with 4/4, ``MIDITimeSignature/default``. Without tempos, CoreMIDI writes a tempo of 120 BPM, ``Tempo/default``.
    ///
    /// - Parameters:
    ///   - metaEvents: The meta events, such as time and key signatures.
    ///   - tempos: The tempo changes.
    public init(metaEvents: [MIDIMetaEvent] = [], tempos: [Tempo] = []) {
        self.metaEvents = metaEvents
        self.tempos = tempos
    }

    /// Creates a tempo track with the given tempo changes and no meta events.
    public init(_ tempos: [Tempo]) {
        self.init(metaEvents: [], tempos: tempos)
    }


    public var description: String {
        self.detailedDescription
    }

    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDITempoTrack>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.tempos)
            descriptor.sequence(for: \.metaEvents)
        }
    }

    public typealias Element = Tempo


    // MARK: - Deprecated names

    @available(*, deprecated, renamed: "metaEvents")
    public var events: [MIDIMetaEvent] {
        get { self.metaEvents }
        set { self.metaEvents = newValue }
    }

    @available(*, deprecated, renamed: "tempos")
    public var contents: [Tempo] {
        get { self.tempos }
        set { self.tempos = newValue }
    }

    @available(*, deprecated, renamed: "init(metaEvents:tempos:)")
    public init(events: [MIDIMetaEvent], tempos: [Tempo] = []) {
        self.init(metaEvents: events, tempos: tempos)
    }


    /// A tempo change.
    public struct Tempo: Sendable, Equatable {

        /// The time of the change, in beats.
        public var timestamp: MusicTimeStamp

        /// The tempo from ``timestamp`` on, in quarter notes per minute.
        public var beatsPerMinute: Double


        /// The default tempo of 120 BPM.
        ///
        /// This is the tempo CoreMIDI writes when a file specifies none.
        public static var `default`: Tempo {
            Tempo(timestamp: 0.0, beatsPerMinute: 120.0)
        }

        /// Creates a tempo change.
        ///
        /// - Parameters:
        ///   - timestamp: The time of the change, in beats.
        ///   - beatsPerMinute: The tempo from `timestamp` on, in quarter notes per minute.
        public init(timestamp: MusicTimeStamp, beatsPerMinute: Double) {
            self.timestamp = timestamp
            self.beatsPerMinute = beatsPerMinute
        }

        @available(*, deprecated, renamed: "beatsPerMinute")
        public var tempo: Double {
            get { self.beatsPerMinute }
            set { self.beatsPerMinute = newValue }
        }

        @available(*, deprecated, renamed: "init(timestamp:beatsPerMinute:)")
        public init(timestamp: MusicTimeStamp, tempo: Double) {
            self.init(timestamp: timestamp, beatsPerMinute: tempo)
        }
    }

}

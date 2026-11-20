//
//  ChannelEvent.swift
//  MIDIKit
//
//  Created by Vaida on 2026-07-04.
//

import AudioToolbox


/// A MIDI channel message other than a note or the sustain pedal.
///
/// Notes are ``MIDINote``s, and the sustain pedal (control change 64) is kept as ``MIDISustainEvent``s. Every other channel voice message of MIDI 1.0 is a channel event:
///
/// | Status | Message |
/// |---|---|
/// | `0xAn` | ``Message/polyphonicKeyPressure(key:pressure:)`` |
/// | `0xBn` | ``Message/controlChange(controller:value:)`` |
/// | `0xCn` | ``Message/programChange(program:)`` |
/// | `0xDn` | ``Message/channelPressure(pressure:)`` |
/// | `0xEn` | ``Message/pitchBend(value:)`` |
///
/// The low nibble `n` of the status byte is the ``channel``.
public struct MIDIChannelEvent: Sendable, Hashable {

    /// The time of the event, in beats.
    public var onset: MusicTimeStamp

    /// The channel, in `0...15`; MIDI channel 1 is `0`.
    public var channel: UInt8

    /// The message, without its channel.
    public var message: Message


    /// Creates a channel event.
    ///
    /// - Parameters:
    ///   - onset: The time of the event, in beats.
    ///   - channel: The channel, in `0...15`.
    ///   - message: The message.
    @inlinable
    public init(onset: MusicTimeStamp, channel: UInt8 = 0, message: Message) {
        assert(channel <= 15, "A MIDI channel is in 0...15")
        self.onset = onset
        self.channel = channel
        self.message = message
    }

    /// Creates a channel event from a channel message read from a sequence.
    ///
    /// - Returns: `nil` if the status is not one of the messages a channel event models.
    init?(onset: MusicTimeStamp, _ message: MIDIChannelMessage) {
        let data1 = message.data1 & 0x7F
        let data2 = message.data2 & 0x7F
        switch message.status & 0xF0 {
        case 0xA0: self.message = .polyphonicKeyPressure(key: data1, pressure: data2)
        case 0xB0: self.message = .controlChange(controller: data1, value: data2)
        case 0xC0: self.message = .programChange(program: data1)
        case 0xD0: self.message = .channelPressure(pressure: data1)
        case 0xE0: self.message = .pitchBend(value: UInt16(data2) << 7 | UInt16(data1)) // LSB first, then MSB
        default: return nil
        }
        self.onset = onset
        self.channel = message.status & 0x0F
    }

    /// The channel message to write to a sequence.
    var channelMessage: MIDIChannelMessage {
        let status: UInt8
        let data1: UInt8
        let data2: UInt8
        switch message {
        case .polyphonicKeyPressure(let key, let pressure): (status, data1, data2) = (0xA0, key, pressure)
        case .controlChange(let controller, let value): (status, data1, data2) = (0xB0, controller, value)
        case .programChange(let program): (status, data1, data2) = (0xC0, program, 0)
        case .channelPressure(let pressure): (status, data1, data2) = (0xD0, pressure, 0)
        case .pitchBend(let value): (status, data1, data2) = (0xE0, UInt8(value & 0x7F), UInt8(value >> 7 & 0x7F))
        }
        return MIDIChannelMessage(status: status | (channel & 0x0F), data1: data1 & 0x7F, data2: data2 & 0x7F, reserved: 0)
    }


    /// A MIDI 1.0 channel voice message, without its channel.
    public enum Message: Sendable, Hashable {

        /// A control change (`0xBn`): a controller, such as 1 for modulation or 67 for the soft pedal, set to a value in `0...127`.
        ///
        /// Controllers `0...119` are ordinary controllers, and `120...127` are channel mode messages, such as 123 for All Notes Off. Controller 64, the sustain pedal, is read as ``MIDISustainEvent``s instead.
        case controlChange(controller: UInt8, value: UInt8)

        /// A program change (`0xCn`): selects the instrument, in `0...127`.
        case programChange(program: UInt8)

        /// A channel pressure, or aftertouch (`0xDn`): one pressure for the whole channel, in `0...127`.
        case channelPressure(pressure: UInt8)

        /// A polyphonic key pressure, or aftertouch (`0xAn`): the pressure on one key, in `0...127`.
        case polyphonicKeyPressure(key: UInt8, pressure: UInt8)

        /// A pitch bend (`0xEn`): a 14-bit value in `0...0x3FFF`, where `0x2000` is no bend.
        case pitchBend(value: UInt16)

    }

}


extension MIDIChannelEvent: CustomStringConvertible {

    public var description: String {
        let onset = self.onset.formatted(.number.precision(.fractionLength(2)))
        let message = switch self.message {
        case .controlChange(let controller, let value): "controlChange(controller: \(controller), value: \(value))"
        case .programChange(let program): "programChange(\(program))"
        case .channelPressure(let pressure): "channelPressure(\(pressure))"
        case .polyphonicKeyPressure(let key, let pressure): "polyphonicKeyPressure(key: \(key), pressure: \(pressure))"
        case .pitchBend(let value): "pitchBend(\(value))"
        }
        return "ChannelEvent(\(onset), channel: \(self.channel), \(message))"
    }

}

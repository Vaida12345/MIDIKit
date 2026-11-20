//
//  MIDITimeSignature.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Foundation
import AudioToolbox


/// The meter of a piece: how many beats a measure holds, and which note value is one beat.
///
/// A time signature is stored in a MIDI time-signature meta event (type `0x58`) as four bytes: the numerator, the denominator as a power of two, the MIDI clocks per metronome click, and the number of 32nd notes in a MIDI quarter note.
public struct MIDITimeSignature: Hashable, Sendable, Codable, CustomStringConvertible {

    /// The number of beats in a measure, the upper number of the time signature, in `1...255`.
    public let numerator: Int

    /// The note value of one beat, the lower number of the time signature: a power of two in `1...128`, such as 4 for a quarter note.
    public let denominator: Int

    /// The number of MIDI clocks per metronome click; 24 clicks once per quarter note.
    public let clocksPerClick: UInt8

    /// The number of 32nd notes in a MIDI quarter note, which is 24 MIDI clocks; normally 8.
    public let thirtySecondNotesPerQuarter: UInt8


    /// Creates a time signature.
    ///
    /// - Parameters:
    ///   - numerator: The number of beats in a measure, in `1...255`.
    ///   - denominator: The note value of one beat: a power of two in `1...128`.
    ///   - clocksPerClick: The number of MIDI clocks per metronome click. The default value is 24, a click per quarter note.
    ///   - thirtySecondNotesPerQuarter: The number of 32nd notes in a MIDI quarter note. The default value is 8.
    public init(_ numerator: Int, _ denominator: Int, clocksPerClick: UInt8 = 24, thirtySecondNotesPerQuarter: UInt8 = 8) {
        precondition(Self.isValid(numerator: numerator, denominator: denominator), "A time signature has a numerator in 1...255 and a denominator that is a power of two in 1...128")
        self.numerator = numerator
        self.denominator = denominator
        self.clocksPerClick = clocksPerClick
        self.thirtySecondNotesPerQuarter = thirtySecondNotesPerQuarter
    }

    /// Creates the time signature stored in a MIDI time-signature meta event.
    ///
    /// - Parameter event: A meta event.
    ///
    /// - Returns: `nil` if `event` is not a time-signature event, has fewer than four bytes, or holds a numerator of 0 or a denominator over 128.
    public init?(_ event: MIDIMetaEvent) {
        guard event.type == 0x58, event.data.count >= 4 else { return nil }
        let bytes = Array(event.data.prefix(4))
        guard bytes[0] > 0, bytes[1] <= 7 else { return nil }
        self.numerator = Int(bytes[0])
        self.denominator = 1 << Int(bytes[1])
        self.clocksPerClick = bytes[2]
        self.thirtySecondNotesPerQuarter = bytes[3]
    }

    /// The data of the time-signature meta event.
    var data: Data {
        Data([UInt8(self.numerator), UInt8(self.denominator.trailingZeroBitCount), self.clocksPerClick, self.thirtySecondNotesPerQuarter])
    }

    /// Returns the time-signature meta event for this time signature.
    ///
    /// - Parameter timestamp: The time of the event, in beats.
    public func event(at timestamp: MusicTimeStamp = 0) -> MIDIMetaEvent {
        MIDIMetaEvent(timestamp: timestamp, type: 0x58, data: self.data)
    }

    public var description: String {
        "\(self.numerator)/\(self.denominator)"
    }

    /// 4/4, with a click per quarter note: the time signature CoreMIDI writes when a file specifies none.
    public static let `default` = MIDITimeSignature(4, 4)


    private static func isValid(numerator: Int, denominator: Int) -> Bool {
        (1...255).contains(numerator) && (1...128).contains(denominator) && denominator.nonzeroBitCount == 1
    }


    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case numerator, denominator, clocksPerClick, thirtySecondNotesPerQuarter
    }

    /// Decodes a time signature.
    ///
    /// - Throws: `DecodingError.dataCorrupted` when the numerator or denominator is out of range.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let numerator = try container.decode(Int.self, forKey: .numerator)
        let denominator = try container.decode(Int.self, forKey: .denominator)
        guard Self.isValid(numerator: numerator, denominator: denominator) else {
            throw DecodingError.dataCorruptedError(forKey: .denominator, in: container, debugDescription: "\(numerator)/\(denominator) is not a valid time signature.")
        }
        self.numerator = numerator
        self.denominator = denominator
        self.clocksPerClick = try container.decode(UInt8.self, forKey: .clocksPerClick)
        self.thirtySecondNotesPerQuarter = try container.decode(UInt8.self, forKey: .thirtySecondNotesPerQuarter)
    }

}

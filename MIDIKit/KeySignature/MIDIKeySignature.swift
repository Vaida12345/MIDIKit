//
//  MIDIKeySignature.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


/// The set of sharps or flats placed after the clef to show which notes are altered throughout the piece.
///
/// A key signature is stored as a signed number of accidentals: positive for sharps, negative for flats, from 7 flats to 7 sharps. This is the same number as the `sf` byte of a MIDI key-signature meta event. A major key and its relative minor share a key signature.
public struct MIDIKeySignature: Hashable, Sendable, Codable, CustomStringConvertible {

    /// The number of sharps, or the negated number of flats, in `-7...7`.
    public let sharps: Int

    /// Creates a key signature from a signed number of accidentals.
    ///
    /// - Parameter sharps: The number of sharps, or the negated number of flats. It must be in `-7...7`.
    public init(sharps: Int) {
        precondition((-7...7).contains(sharps), "A key signature has at most 7 sharps or flats")
        self.sharps = sharps
    }

    /// The key signature of the major key with the given tonic.
    ///
    /// Enharmonic keys are spelled with fewer accidentals, and with flats on a tie: G♭ (6 flats) rather than F♯, B (5 sharps) rather than C♭, and D♭ (5 flats) rather than C♯.
    ///
    /// - Parameter tonic: The pitch class of the tonic, with C = 0.
    public init(majorTonic tonic: Int) {
        let fifths = ((tonic % 12 + 12) % 12 &* 7) % 12
        self.sharps = fifths <= 5 ? fifths : fifths &- 12
    }

    /// Creates the key signature stored in a MIDI key-signature meta event.
    ///
    /// A key-signature meta event (type `0x59`) holds the signed number of sharps (`sf`) in its first byte, followed by the mode (`mi`), which is ignored.
    ///
    /// - Parameter event: A meta event.
    ///
    /// - Returns: `nil` if `event` is not a key-signature event, has no data, or holds more than 7 sharps or flats.
    public init?(_ event: MIDIMetaEvent) {
        guard event.type == 0x59, let first = event.data.first else { return nil }
        let sharps = Int(Int8(bitPattern: first))
        guard (-7...7).contains(sharps) else { return nil }
        self.sharps = sharps
    }

    /// Whether the accidentals are sharps or flats, or `neutral` when there are none.
    public var accidental: Accidental {
        sharps > 0 ? .sharp : sharps < 0 ? .flat : .neutral
    }

    /// The pitch classes altered by this key signature, with C = 0, in the order the accidentals are written.
    ///
    /// Each value is the pitch class of the note before alteration: the first sharp is F (5), and the first flat is B (11).
    public var pitches: [Int] {
        switch accidental {
        case .sharp: Array(Self.sharpOrder.prefix(sharps))
        case .flat: Array(Self.flatOrder.prefix(-sharps))
        case .neutral: []
        }
    }

    /// The tonic of the major key with this key signature, with C = 0.
    public var majorTonic: Int {
        ((sharps &* 7) % 12 + 12) % 12
    }

    public var description: String {
        switch accidental {
        case .sharp: "\(sharps)♯"
        case .flat: "\(-sharps)♭"
        case .neutral: "♮"
        }
    }

    /// The key signature without sharps or flats, of C major and A minor.
    public static let natural = MIDIKeySignature(sharps: 0)

    /// The order sharps are written in: F, C, G, D, A, E, B.
    private static let sharpOrder = [5, 0, 7, 2, 9, 4, 11]

    /// The order flats are written in: B, E, A, D, G, C, F.
    private static let flatOrder = [11, 4, 9, 2, 7, 0, 5]


    /// Whether the accidentals of a key signature are sharps or flats.
    public enum Accidental: Int, CaseIterable, Hashable, Sendable, Codable {
        case flat = -1
        case neutral = 0
        case sharp = 1
    }


    // MARK: - Coding

    // The format of `IndexedContainer.KeySignature`, from MIDIKit 1.x.
    private enum LegacyCodingKeys: String, CodingKey {
        case pitches, accidental
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.sharps)
    }

    /// Decodes a key signature, in either its own format or the format of `IndexedContainer.KeySignature` from MIDIKit 1.x.
    ///
    /// - Throws: `DecodingError.dataCorrupted` when the value is not one of the 15 standard key signatures.
    public init(from decoder: any Decoder) throws {
        // `singleValueContainer()` succeeds on any value, so check that it holds a number before choosing this format.
        if let container = try? decoder.singleValueContainer(), let sharps = try? container.decode(Int.self) {
            guard (-7...7).contains(sharps) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "A key signature has at most 7 sharps or flats, found \(sharps).")
            }
            self.sharps = sharps
        } else {
            let container = try decoder.container(keyedBy: LegacyCodingKeys.self)
            // The legacy format: the altered pitch classes, and whether they are sharps or flats.
            let accidental = try container.decode(Accidental.self, forKey: .accidental)
            let pitches = try container.decode([Int].self, forKey: .pitches)
            let order = accidental == .sharp ? Self.sharpOrder : Self.flatOrder
            guard pitches.count <= 7, accidental != .neutral || pitches.isEmpty, pitches == Array(order.prefix(pitches.count)) else {
                throw DecodingError.dataCorruptedError(forKey: .pitches, in: container, debugDescription: "\(pitches) with \(accidental) is not a standard key signature.")
            }
            self.sharps = accidental.rawValue &* pitches.count
        }
    }

}

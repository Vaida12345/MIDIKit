//
//  Note + Description.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//


extension MIDINote {
    
    /// The diatonic scale.
    ///
    /// To obtain a description of key, consider
    /// ```swift
    /// let (group, index, isSharp) = Keys.determine(note: 30) // 0-based index
    /// "\(Keys.diatonicScale[index])\(isSharp ? "#" : "")\(group - 1)"
    /// ```
    @inlinable
    public static var diatonicScale: [String] {
        ["C", "D", "E", "F", "G", "A", "B"]
    }
    
    /// - Parameters:
    ///   - note: 0-based indexed note
    ///
    /// - Returns: 0-based indexed values.
    @inlinable
    public static func determine(note: some BinaryInteger) -> (group: Int, index: Int, isSharp: Bool) {
        // layout [1, 1#, 2, 2#, 3, 4, 4#, 5, 5#, 6, 6#, 7], 12 in total
        //        [0, 1,  2, 3,  4, 5, 6,  7, 8,  9, 10, 11]
        
        let (group, index) = Int(note).quotientAndRemainder(dividingBy: 12)
        
        let shiftedIndex: Int
        let isSharp: Bool
        
        switch index {
        case 0:
            isSharp = false
            shiftedIndex = 1
            
        case 1:
            isSharp = true
            shiftedIndex = 1
            
        case 2:
            isSharp = false
            shiftedIndex = 2
            
        case 3:
            isSharp = true
            shiftedIndex = 2
            
        case 4:
            isSharp = false
            shiftedIndex = 3
            
        case 5:
            isSharp = false
            shiftedIndex = 4
            
        case 6:
            isSharp = true
            shiftedIndex = 4
            
        case 7:
            isSharp = false
            shiftedIndex = 5
            
        case 8:
            isSharp = true
            shiftedIndex = 5
            
        case 9:
            isSharp = false
            shiftedIndex = 6
            
        case 10:
            isSharp = true
            shiftedIndex = 6
            
        case 11:
            isSharp = false
            shiftedIndex = 7
            
        default:
            fatalError("Invalid note index: \(index)")
        }
        
        return (group, shiftedIndex - 1, isSharp)
    }
    
    /// This project uses standard MIDI notation.
    ///
    /// - Middle C is MIDI note 60, labeled as C4.
    /// - Leftmost key: MIDI note 21 (A0).
    /// - Rightmost key: MIDI note 108 (C8).
    @inlinable
    public static func description(for note: some BinaryInteger) -> String {
        let index = determine(note: Int(note))
        return "\(MIDINote.diatonicScale[index.index])\(index.group - 1)\(index.isSharp ? "#" : "")"
    }
    
}

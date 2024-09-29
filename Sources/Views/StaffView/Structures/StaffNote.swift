//
//  StaffNote.swift
//  MIDIKit
//
//  Created by Vaida on 9/28/24.
//

import Foundation


public struct StaffNote: Identifiable, CustomStringConvertible, Hashable {
    
    /// The onset, in beats.
    public var onset: Double
    
    /// The offset, in beats.
    public var offset: Double
    
    /// The key
    public var note: UInt8
    
    /// The duration of the note, on set, it changes the ``offset``, while ``onset`` remains the same.
    public var duration: Double {
        get {
            self.offset - self.onset
        }
        set {
            self.offset = self.onset + newValue
        }
    }
    
    public var description: String {
        let (group, index, isSharp) = self.determineNote()
        
        return "\(["C", "D", "E", "F", "G", "A", "B"][Int(group)])\(isSharp ? "#" : "")\(index)"
    }
    
    var measure: StaffMeasure? = nil
    
    func determineNote() -> (group: UInt8, index: UInt8, isSharp: Bool) {
        // layout [1, 1#, 2, 2#, 3, 4, 4#, 5, 5#, 6, 6#, 7], 12 in total
        //        [0, 1,  2, 3,  4, 5, 6,  7, 8,  9, 10, 11]
        
        let (group, index) = self.note.quotientAndRemainder(dividingBy: 12)
        
        let shiftedIndex: UInt8
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
    
    /// Calculates the distance to middle C, midi key 60, for drawing purposes.
    ///
    /// For the purpose here, notes can only be sharp or none.
    func distanceToMiddleC() -> Int {
        let (group, index, _) = determineNote()
        
        let middleC = 5 * 7
        
        return abs(middleC - Int(group * 7 + index))
    }
    
    var isSharp: Bool {
        determineNote().isSharp
    }
    
//    /// Whether it should be shown as sharp. This state is used for graphing only.
//    var _showSharp: Bool = false
    
    
    public let id: UUID = UUID()
    
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (_ lhs: StaffNote, _ rhs: StaffNote) -> Bool {
        lhs.id == rhs.id
    }
    
}

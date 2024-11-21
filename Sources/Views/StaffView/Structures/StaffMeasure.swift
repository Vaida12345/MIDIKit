//
//  StaffMeasure.swift
//  MIDIKit
//
//  Created by Vaida on 9/29/24.
//

import Observation


@Observable
final class StaffMeasure: UndoTracking {
    
    var notes: [StaffNote] = []
    
    
    init(notes: [StaffNote] = []) {
        self.notes = notes
    }
    
}

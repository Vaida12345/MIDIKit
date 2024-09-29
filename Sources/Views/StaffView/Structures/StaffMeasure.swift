//
//  StaffMeasure.swift
//  MIDIKit
//
//  Created by Vaida on 9/29/24.
//

import Observation
import Stratum


@Observable
final class StaffMeasure: UndoTracking {
    
    var notes: [StaffNote] = []
    
    
    init(notes: [StaffNote] = []) {
        self.notes = notes
    }
    
}

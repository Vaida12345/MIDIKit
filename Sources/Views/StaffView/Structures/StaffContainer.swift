//
//  StaffContainer.swift
//  MIDIKit
//
//  Created by Vaida on 9/28/24.
//

import Foundation
import Observation


@Observable
final class StaffContainer: UndoTracking {
    
    var notes: [StaffNote]
    
    var selection: Set<StaffNote> = []
    
    var measures: [StaffMeasure] = []
    
//    func prepareForGraph() -> [StaffNote] {
//
//    }
    
    init(notes: [StaffNote]) {
        self.notes = notes
    }
    
}

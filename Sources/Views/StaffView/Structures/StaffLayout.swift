//
//  StaffLayout.swift
//  MIDIKit
//
//  Created by Vaida on 9/28/24.
//

import Observation


@Observable
final class StaffLayout {
    
    /// The vertical spacing between each staff line
    var staffLineSpacing: Double = 20
    
    /// The horizontal distance between beats.
    var beatLength: Double = 160
    
    /// The line width for drawing staff lines.
    var lineWidth: Double = 2
    
    
    init() {
        
    }
    
}

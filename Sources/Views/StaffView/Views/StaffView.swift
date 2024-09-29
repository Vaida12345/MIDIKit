//
//  StaffView.swift
//  MIDIKit
//
//  Created by Vaida on 9/28/24.
//


import SwiftUI


public struct StaffView: View {
    
    let container: StaffContainer
    
    let layout = StaffLayout()
    
    public var body: some View {
        ZStack(alignment: .leading) {
            ForEach(container.notes) { note in
                NoteView(note: note)
                    .offset(y: 60)
                    .offset(x: layout.beatLength * note.onset)
            }
            .contextMenu {
                SelectionContextMenu()
            }
            
            StaffLines()
        }
        .environment(layout)
        .environment(container)
    }
    
}

#Preview {
    StaffView(container: StaffContainer(notes: MIDINotes.preview.map({ StaffNote(onset: $0.onset, offset: $0.offset, note: $0.note) })))
//    StaffView(notes: [StaffNote(note: MIDINote(onset: 1, offset: 1.5, note: 60, velocity: 1, channel: 0))])
}

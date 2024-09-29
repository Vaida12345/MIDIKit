//
//  SelectionContextMenu.swift
//  MIDIKit
//
//  Created by Vaida on 9/29/24.
//

import SwiftUI


struct SelectionContextMenu: View {
    
    @Environment(StaffContainer.self) private var container
    
    @Environment(\.undoManager) private var undoManager
    
    
    var body: some View {
        Section("Measures") {
            Button("Put in last measure") {
                undoManager?.beginUndoGrouping()
                undoManager?.setActionName("Put \(container.selection.map(\.description).joined(separator: ", ")) in last measure")
                
                container.removeAll(from: \.notes, undoManager: undoManager, where: { container.selection.contains($0) })
                container.measures.last?.append(contentsOf: container.selection, to: \.notes, undoManager: undoManager)
                
                undoManager?.endUndoGrouping()
            }
            .disabled(container.measures.isEmpty)
            
            Button("Put in new measure") {
                undoManager?.beginUndoGrouping()
                undoManager?.setActionName("Put \(container.selection.map(\.description).joined(separator: ", ")) in last measure")
                
                container.removeAll(from: \.notes, undoManager: undoManager, where: { container.selection.contains($0) })
                container.append(StaffMeasure(notes: Array(container.selection)), to: \.measures, undoManager: undoManager)
                
                undoManager?.endUndoGrouping()
            }
        }
        .disabled(container.selection.contains(where: { $0.measure != nil }))
        
        Divider()
        
        Button("Help") {
            
        }
    }
}

#Preview {
    VStack {
        SelectionContextMenu()
    }
    .buttonStyle(.plain)
    .environment(StaffContainer(notes: []))
}

#Preview {
    Text("control-click me")
        .contextMenu {
            SelectionContextMenu()
        }
        .environment(StaffContainer(notes: []))
        .padding()
}


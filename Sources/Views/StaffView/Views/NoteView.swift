//
//  NoteView.swift
//  MIDIKit
//
//  Created by Vaida on 9/28/24.
//

import SwiftUI


struct NoteView: View {
    
    var note: StaffNote
    
    var verticalSpacing: Double {
        layout.staffLineSpacing
    }
    
    var staffPosition: CGFloat {
        // Assuming middle C (MIDI 60) is the reference for note positions
        Double(note.distanceToMiddleC()) * verticalSpacing / 2
    }
    
    var isSelected: Bool {
        container.selection.contains(note)
    }
    
    @Environment(StaffLayout.self) private var layout
    
    @Environment(StaffContainer.self) private var container
    
    @Environment(\.undoManager) private var undoManager
    
    
    fileprivate var sheetNote: SheetNoteView {
        let duration = note.duration
        
        // one beat is quarter note
        let note = duration / 4
        
        if note <= 1/128      { return ._1_128 }
        if note <= 1/64 * 3/2 { return ._1_64 }
        if note <= 1/32 * 3/2 { return ._1_32 }
        if note <= 1/16 * 3/2 { return ._1_16 }
        if note <= 1/8 * 3/2  { return ._1_8 }
        if note <= 1/4 * 3/2  { return .quarter }
        if note <= 1/2 * 3/2  { return .half }
        
        return .full
    }
    
    var body: some View {
        ZStack {
            AuxiliaryLines(note: note)
            
            Button {
                container.replace(
                    \.selection,
                     with: [note],
                     undoManager: undoManager) { notes in
                         "Select \(notes.map(\.description).joined(separator: ", "))"
                     }
            } label: {
                sheetNote
                    .sharp(note.isSharp)
                    .offset(y: note.note < 60 ? staffPosition : -staffPosition)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AuxiliaryLines: View {
    
    // The center note is 60
    // that makes the lower bound of the staff 60, upper bound 72
    let note: StaffNote
    
    var verticalSpacing: Double {
        layout.staffLineSpacing
    }
    
    var lineWidth: Double {
        layout.lineWidth
    }
    
    var paddings: Double {
        lineWidth / 2
    }
    
    @Environment(StaffLayout.self) private var layout
    
    var height: Double {
        offset * 2 + lineWidth * 2
    }
    
    var offset: Double {
        let (group, index, _) = note.determineNote()
        let note = group * 7 + index
        
        return Double(max(35 - Int(note), Int(note) - 48) / 2) * verticalSpacing / 2
    }
    
    var staffHeight: Double {
        verticalSpacing * 4
    }
    
    var body: some View {
        Canvas { context, size in
            let (group, index, _) = note.determineNote()
            // from group 5, 0 to group 6, 6
            let note = group * 7 + index
            
            if note >= 48 {
                var verticalPosition: Double = lineWidth
                for _ in stride(from: 48, through: note, by: 2) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: verticalPosition))
                    path.addLine(to: CGPoint(x: size.width, y: verticalPosition))
                    
                    context.stroke(path, with: .foreground, lineWidth: 2)
                    
                    verticalPosition += verticalSpacing
                }
            } else if note <= 35 {
                var verticalPosition: Double = lineWidth
                for _ in stride(from: note, through: 35, by: 2) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: verticalPosition))
                    path.addLine(to: CGPoint(x: size.width, y: verticalPosition))
                    
                    context.stroke(path, with: .foreground, lineWidth: 2)
                    
                    verticalPosition += verticalSpacing
                }
            }
        }
        .frame(width: 35, height: height)
        .offset(y: note.note <= 61 ? offset : -offset - staffHeight - 40)
    }
    
}

private struct SheetNoteView: View {
    
    let note: String
    
    let offset: Double
    
    var isSharp: Bool = false
    
    var body: some View {
        ZStack {
            Text(note)
                .font(.custom("Bravura", fixedSize: 70))
                .offset(x: offset)
                .frame(width: 80)
            
            if isSharp {
                Text("\u{E262}")
                    .font(.custom("Bravura", fixedSize: 70))
                    .offset(x: -25, y: 3)
            }
        }
    }
    
    
    static let full: SheetNoteView = SheetNoteView(note: "\u{E1D2}", offset: 0)
    static let half: SheetNoteView = SheetNoteView(note: "\u{E1D3}", offset: 0)
    static let quarter: SheetNoteView = SheetNoteView(note: "\u{E1D5}", offset: 0)
    static let _1_8: SheetNoteView = SheetNoteView(note: "\u{E1D7}", offset: 8)
    static let _1_16: SheetNoteView = SheetNoteView(note: "\u{E1D9}", offset: 8)
    static let _1_32: SheetNoteView = SheetNoteView(note: "\u{E1DB}", offset: 8)
    static let _1_64: SheetNoteView = SheetNoteView(note: "\u{E1DD}", offset: 8)
    static let _1_128: SheetNoteView = SheetNoteView(note: "\u{E1DF}", offset: 8)
    
    
    func sharp(_ isSharp: Bool = true) -> SheetNoteView {
        SheetNoteView(note: self.note, offset: self.offset, isSharp: isSharp)
    }
    
}

#Preview {
    ZStack {
        SheetNoteView._1_8
            .sharp(true)
        
        Rectangle()
            .fill(.foreground)
            .frame(width: 1, height: 200)
    }
    .environment(StaffLayout())
    .environment(StaffContainer(notes: []))
}

#Preview {
    ZStack {
        NoteView(note: StaffNote(onset: 0, offset: 1, note: 58))
            .offset(y: 60)
        
        StaffLines()
    }
    .environment(StaffLayout())
    .environment(StaffContainer(notes: []))
}

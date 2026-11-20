//
//  Container + Transfer.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-13.
//

import CoreTransferable


extension MIDIContainer: Transferable {
    
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .midi) { container in
            try container.data()
        } importing: { data in
            try MIDIContainer(data: data)
        }

    }
    
}

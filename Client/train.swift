//
//  train.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-24.
//

#if os(macOS)
import FinderItem
import Foundation
import MIDIKit
import DetailedDescription
import SwiftUI
import Essentials
import Accelerate


func train() async throws {
    var _features: [[[Float]]] = []
    var hands: [[Float]] = []
    
    let folder: FinderItem = "/Users/vaida/DataBase/Machine Learning/InferHand"
    for child in try (folder/"asap-dataset-master").children(range: .enumeration) {
        guard child.extension == "mid" else { continue }
        guard let container = try? MIDIContainer(at: child) else { continue }
        guard container.tracks.count == 2 else { continue }
        let new = await container.indexed()._extractMIDINoteFeatures()
        _features.append(new.0)
        hands.append(new.1)
    }
    
    print("Input size: \(_features[0][0].count), _, \(_features.count)")
    let flatFeatures = _features.flatten()
    
    
    try """
_X = \(_features)
_y = \(hands)
""".write(to: folder/"dataset.py")
    
    let validation = try [
        MIDIContainer(at: folder/"桜廻廊.mid"),
        MIDIContainer(at: "/Users/vaida/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Others/Sheet/Sheet/Angel Beats/Angel_Beats_Medley_animenz/Angel_Beats_Medley_animenz.mid"),
    ]
    var validation_features: [[[Float]]] = []
    var validation_hands: [[Float]] = []
    for validation in validation {
        let new = await validation.indexed()._extractMIDINoteFeatures()
        validation_features.append(new.0)
        validation_hands.append(new.1)
    }
    
    
    try """
_X_val = \(validation_features)
_y_val = \(validation_hands)
""".write(to: folder/"validation.py")
}
#endif

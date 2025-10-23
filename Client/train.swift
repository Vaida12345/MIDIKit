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
    
    let folder: FinderItem = "/Volumes/Users/Shiin/Desktop/Hands"
    for child in try (folder/"asap-dataset-master").children(range: .enumeration) {
        guard child.extension == "mid" else { continue }
        guard let container = try? MIDIContainer(at: child) else { continue }
        guard container.tracks.count == 2 else { continue }
        
        let indexed = container.indexed()
        await indexed.normalize(preserve: .notesDisplay)
        let new = await indexed._extractMIDINoteFeatures()
        _features.append(new.0)
        hands.append(new.1)
    }
    
    print("Input size: \(_features[0][0].count), _, \(_features.count)")
    
//    // MARK: - get mean, std
//    let flatten = _features.flatten()
//    var transposed: [[Float]] = .init(repeating: .init(), count: flatten[0].count)
//    for i in 0..<flatten[0].count {
//        for j in 0..<flatten.count {
//            transposed[i].append(flatten[j][i])
//        }
//    }
//    
//    let z_index_features = [8, 9, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38] + [Int](40..<85)
//    print(transposed.enumerated().filter({ z_index_features.contains($0.0) }).map({ vDSP.mean($0.1) }))
//    print(transposed.enumerated().filter({ z_index_features.contains($0.0) }).map({ vDSP.standardDeviation($0.1) }))
    
    try await write(array: _features, name: "dataset")
    try """
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
    
    func write(array: [[[Float]]], name: String) async throws {
        print(array.count)
        
        // Flatten data
        var flatData = [Float]()
        var offsets = [Int]()
        var current = 0
        
        for subarray in array {
            offsets.append(current)
            for inner in subarray {
                flatData.append(contentsOf: inner)
                current += inner.count
                
                if !inner.allSatisfy({ !$0.isNaN && !$0.isInfinite }) {
                    for (index, value) in inner.enumerated() {
                        print(index, value)
                    }
                }
            }
        }
        offsets.append(current)
        
        try flatData.withUnsafeMutableBufferPointer { flatData in
            // Write binary
            let data = Data(bytesNoCopy: flatData.baseAddress!, count: flatData.count * MemoryLayout<Float>.size, deallocator: .none)
            try data.write(to: folder/"\(name)_data.bin")
        }
        
        try offsets.withUnsafeMutableBufferPointer { offsetsData in
            let data = Data(bytesNoCopy: offsetsData.baseAddress!, count: offsetsData.count * MemoryLayout<Int>.size, deallocator: .none)
            try data.write(to: folder/"\(name)_offsets.bin")
        }
    }
}
#endif

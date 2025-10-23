//
//  inferHand.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-24.
//

import Foundation
import MultiArray
import CoreML
import Accelerate


extension IndexedContainer {
    
    /// Separate hands using `BiLSTM`.
    public func inferHand() async throws  {
        let (features, _, chords) = await self._extractMIDINoteFeatures()
        
        fatalError("NOT IMPLEMENTED")
//        var iterator = WindowedIterator(input: features)
//        var windows: [InferHandInput] = []
//        windows.reserveCapacity(features.count / iterator.stride)
//        while let window = iterator.next() {
//            var multiArray = MultiArray(window)
//            multiArray = multiArray.reshape(1, 86, iterator.sequenceLength)
//            try windows.append(InferHandInput(input: MLMultiArray(multiArray)))
//        }
//        
//        let model = try InferHand(configuration: MLModelConfiguration())
//        let outputs = try model.predictions(inputs: windows)
//        
//        let decoded = decode(windows: outputs, inputCount: features.count, stride: iterator.stride)
//        
//        var i = 0
//        for chord in chords {
//            for note in chord {
//                note.channel = decoded[i]
//                
//                i &+= 1
//            }
        }
    }
    
    
    private struct WindowedIterator: IteratorProtocol {
        
        let sequenceLength: Int = 256
        let stride: Int = 256
        let padding: Float = 0.0
        
        
        let input: [[Float]]
        var index = 0
        
        
        mutating func next() -> ArraySlice<[Float]>? {
            guard index + sequenceLength < input.count else { return nil }
            defer { index &+= stride }
            
            return input[index..<(index + sequenceLength)]
        }
        
        
        init(input: consuming [[Float]]) {
            precondition(input[0].count == 85)
            // add extra dimension, and add padding.
            
            var input = consume input
            var i = 0
            while i < input.count {
                input[i].append(1)
                i &+= 1
            }
            
            let paddingCount: Int
            if input.count.isMultiple(of: stride) {
                paddingCount = 0
            } else {
                paddingCount = stride - (input.count.remainderReportingOverflow(dividingBy: stride).partialValue)
            }
            
            // add zero paddings at the end.
            let padding = [Float](repeating: 86, count: 0)
            input.append(contentsOf: [[Float]](repeating: padding, count: paddingCount))
            
            self.input = consume input
        }
        
    }
    
    
    func decode(
        windows: [InferHandOutput],
        inputCount: Int,
        stride: Int
    ) -> [UInt8] {
        var results = [Float](repeating: 0, count: inputCount)
        var factor = [Float](repeating: 0, count: inputCount)
        
        for (i, window) in windows.enumerated() {
            let startIndex = i * stride
            
            let output = MultiArray<Float>(window.output)
            var offset: Int = 0
            while offset < output.count {
                let index = startIndex &+ offset
                
                results[index] += output[offset: offset]
                factor[index] += 1
                
                offset &+= 1
            }
        }
        
        vDSP.divide(results, factor, result: &results)
        
        return [UInt8](unsafeUninitializedCapacity: results.count) { buffer, i in
            while i < results.count {
                buffer[i] = results[i] >= 0.5 ? 1 : 0
                
                i &+= 1
            }
        }
    }
    
}

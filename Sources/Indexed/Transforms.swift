//
//  Transforms.swift
//  MIDIKit
//
//  Created by Vaida on 12/23/24.
//

import DetailedDescription


extension IndexedContainer {
    
    /// Applies the velocity info to `other`.
    ///
    /// This intended use case is when
    /// - `self` is transcribed by `PianoTranscription`
    ///   - velocity is correct but onset / offset is not
    /// - `other` is normalized by hand.
    ///   - velocity is incorrect.
    ///
    /// `self` will not be mutated.
    public func applyVelocity(to other: IndexedContainer) {
        
    }
    
//    /// Align self to `other`.
//    public func align(
//        to other: IndexedContainer
//    ) async {
//        guard !self.combinedNotes.isEmpty && !other.combinedNotes.isEmpty else { return }
//        
//        let interval: Double = 1/2 // 1/8 note
//        let lhsFeatures = await self.keyFeatures(interval: interval)
//        let rhsFeatures = await other.keyFeatures(interval: interval)
//        
//        var checks: [(lhs: Int, rhs: Int)] = []
//        var lhsIndex = 0
//        var rhsIndex = 0
//        
//        func isConsecutive(_ features: KeyFeatures, _ lhs: Int, _ rhs: Int) -> Bool {
//            
////            print(features[lhs])
////            print(features[rhs])
//            print(similarity)
//            return
//        }
//        
//        while lhsIndex &+ 1 < lhsFeatures.count && rhsIndex &+ 1 < rhsFeatures.count {
//            let leftSimilarity = lhsFeatures[lhsIndex].similarity(to: lhsFeatures[lhsIndex &+ 1])
//            let rightSimilarity = rhsFeatures[rhsIndex].similarity(to: rhsFeatures[rhsIndex &+ 1])
//            // check left and rhs vectors
//            let isSimilar = zip(leftSimilarity, rightSimilarity).map({ lhs, rhs in
//                switch (lhs, rhs) {
//                case (0, 0): return true
//                case (1, 1): return true
//                case (_, 0): return false
//                case (_, 1): return false
//                case (0, _): return false
//                case (1, _): return false
//                default: return true
//                }
//            }).allSatisfy(\.self)
//            
//            if isSimilar {
//                checks.append((lhsIndex, rhsIndex))
//                lhsIndex &+= 1
//                rhsIndex &+= 1
//            } else {
//                // branching?
//                
//            }
//            
//            // roll
//           
//            while rhsIndex &+ 1 < rhsFeatures.count, isConsecutive(rhsFeatures, rhsIndex, rhsIndex &+ 1) {
////                print("roll r")
//                rhsIndex &+= 1
//            }
//        }
//        
//        detailedPrint(checks)
//    }
    
}

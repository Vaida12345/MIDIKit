//
//  ArrayRepresentable.swift
//  MIDIKit
//
//  Created by Vaida on 12/24/24.
//

public protocol ArrayRepresentable: ExpressibleByArrayLiteral, RandomAccessCollection where Index == Int, ArrayLiteralElement == Element {
    
    var contents: [Element] { get set }
    
    init(_ contents: [Element])
    
}

public extension ArrayRepresentable {
    
    @inlinable var startIndex: Index { 0 }
    @inlinable var endIndex: Index { self.contents.count }
    @inlinable var count: Index { self.contents.count }
    
    @inlinable
    subscript(position: Index) -> Element {
        get {
            self.contents[position]
        }
        set {
            self.contents[position] = newValue
        }
    }
    
    @inlinable
    init(arrayLiteral elements: ArrayLiteralElement...) {
        self.init(elements)
    }
    
    @inlinable
    mutating func forEach(body: (_ index: Index, _ element: inout Element) -> Void) {
        var i = 0
        while i < self.endIndex {
            body(i, &self[i])
            
            i &+= 1
        }
    }
    
}

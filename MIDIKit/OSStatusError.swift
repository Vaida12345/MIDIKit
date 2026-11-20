//
//  OSStatusError.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import Essentials
import Foundation
import CoreFoundation


public struct OSStatusError: GenericError {
    
    /// The OSStatus Error Code.
    public let code: OSStatus
    
    public var message: String {
        NSError(domain: kCFErrorDomainOSStatus as String, code: Int(code)).localizedDescription
    }
    
    public var details: String? {
        NSError(domain: kCFErrorDomainOSStatus as String, code: Int(code)).debugDescription
    }
    
    @inlinable
    init(code: OSStatus) {
        self.code = code
    }
}


@inlinable
func withErrorCaptured(_ block: () throws -> OSStatus) throws {
    let code = try block()
    guard code == noErr else { throw OSStatusError(code: code) }
}

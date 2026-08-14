//
//  MIDIInputController.swift
//  MIDIKit
//
//  Created by Vaida on 2026-08-14.
//

import CoreMIDI
import Essentials
import OSLog


/// Coordinates connections to Core MIDI input sources and publishes their incoming events.
///
/// ## Lifecycle
///
/// Keep one controller for the part of your app that receives MIDI—normally
/// ``MIDIInputController/shared``. At each stage, use the following API:
///
/// 1. **Prepare:** Call ``initialize()`` if you want to report setup failures before a
///    source is selected. This is optional because ``connect(to:)`` initializes lazily.
/// 2. **Choose and connect:** Show ``availableSources`` and pass the selected source to
///    ``connect(to:)``. For an automatic default, call ``connectToFirstAvailableSource()``.
/// 3. **Receive:** Iterate over a new stream from ``events()`` in a task. Each caller gets
///    an independent stream; cancel that task when the receiving view or feature ends.
/// 4. **Reconnect or finish:** When a new input source appears while no source is connected,
///    the controller connects to it automatically. Set ``automaticallyReconnect`` before
///    connecting when a temporarily unavailable preferred device should reconnect. Call
///    ``disconnect()`` when input is no longer needed or when the person explicitly disconnects.
@MainActor
@Observable
public final class MIDIInputController {
    
    @ObservationIgnored
    private var midiClient = MIDIClientRef()
    
    @ObservationIgnored
    private var inputPort = MIDIPortRef()
    
    @ObservationIgnored
    private var eventContinuations: [UUID: AsyncStream<MIDIInputEvent>.Continuation] = [:]
    
    @ObservationIgnored
    private var hasCreatedMIDIClient = false
    
    @ObservationIgnored
    private var hasCreatedInputPort = false
    
    @ObservationIgnored
    private var preferredSourceID: MIDIUniqueID?
    
    private let logger = Logger(subsystem: "MIDIInputController", category: "Connection")
    
    /// All currently online MIDI input sources with active network connections.
    ///
    /// This excludes the default Network MIDI source until its session is enabled and connected,
    /// while retaining connected Bluetooth and other Core MIDI sources.
    public private(set) var availableSources: [Source] = []
    
    /// The source currently connected to the input port.
    public private(set) var connectedSource: Source?
    
    /// Whether the controller reconnects to the preferred source after the MIDI setup changes.
    @ObservationIgnored
    public var automaticallyReconnect = true
    
    /// The process-wide MIDI input coordinator.
    public nonisolated static let shared = MIDIInputController()
    
    
    private nonisolated init() {}
    
    
    /// Refreshes the observable source snapshot from Core MIDI's current endpoint registry.
    private func refreshAvailableSources() {
        availableSources = currentAvailableSources()
    }
    
    /// Returns a fresh snapshot of the currently online MIDI input sources.
    private func currentAvailableSources() -> [Source] {
        let networkSession = MIDINetworkSession.default()
        let networkSource = networkSession.sourceEndpoint()
        
        return (0..<MIDIGetNumberOfSources())
            .compactMap(MIDIGetSource)
            .filter { source in
                guard source == networkSource else { return true }
                return networkSession.isEnabled && !networkSession.connections().isEmpty
            }
            .compactMap(Source.init)
    }
    
    /// Creates the Core MIDI client and refreshes the initial source snapshot.
    ///
    /// This method deliberately defers creating the input port until a source connects, keeping
    /// app-start setup limited to the client registration required for setup notifications.
    public func initialize() throws {
        guard !hasCreatedMIDIClient else { return }
        
        // Core MIDI invokes this block on an arbitrary thread.
        let clientStatus = MIDIClientCreateWithBlock("MIDIKit Input" as CFString, &midiClient) { @Sendable [weak self] notification in
            let messageID = notification.pointee.messageID
            let changedEndpoint: MIDIEndpointRef?
            
            switch messageID {
            case .msgObjectAdded, .msgObjectRemoved:
                changedEndpoint = notification.withMemoryRebound(to: MIDIObjectAddRemoveNotification.self, capacity: 1) {
                    $0.pointee.child
                }
            default:
                changedEndpoint = nil
            }
            
            let logger = Logger(subsystem: "MIDIKit", category: "MIDIInput")
            switch messageID {
            case .msgObjectAdded: logger.info("Received object added")
            case .msgSetupChanged: logger.info("Received setup changed")
            case .msgObjectRemoved: logger.info("Received object removed")
            default: logger.info("Received message")
            }
            
            Task { @MainActor [weak self] in
                self?.handle(messageID: messageID, changedEndpoint: changedEndpoint)
            }
        }
        guard clientStatus == noErr else {
            logger.error("Failed to create MIDI client: \(clientStatus)")
            throw ConnectError.cannotCreateClient
        }
        
        hasCreatedMIDIClient = true
        refreshAvailableSources()
    }
    
    /// Creates the input port when a source is about to connect.
    private func createInputPortIfNeeded() throws {
        guard !hasCreatedInputPort else { return }
        
        // Core MIDI invokes this block on a separate high-priority receive thread.
        let receiveBlock: @Sendable (UnsafePointer<MIDIEventList>, UnsafeMutableRawPointer?) -> Void = { [weak self] eventList, _ in
            guard let self else { return }
            let contextPointer = Unmanaged.passUnretained(self).toOpaque()
            
            MIDIEventListForEachEvent(eventList, { contextPointer, timestamp, message in
                guard let contextPointer else { return }
                let controller = Unmanaged<MIDIInputController>.fromOpaque(contextPointer).takeUnretainedValue()
                let event = MIDIInputEvent(timestamp: timestamp, message: message)
                
                Task { @MainActor [weak controller] in
                    controller?.publish(event)
                }
            }, contextPointer)
        }
        
        let portStatus = MIDIInputPortCreateWithProtocol(
            midiClient,
            "MIDIKit Input Port" as CFString,
            ._1_0,
            &inputPort,
            receiveBlock
        )
        guard portStatus == noErr else {
            logger.error("Failed to create MIDI input port: \(portStatus)")
            throw ConnectError.cannotCreateInputPort
        }
        
        hasCreatedInputPort = true
    }
    
    /// Connects the input port to a specific MIDI source.
    ///
    /// The source becomes the preferred source for automatic reconnection.
    public func connect(to source: Source) throws {
        try initialize()
        try createInputPortIfNeeded()
        disconnect(preservingPreferredSource: true)
        
        guard MIDIPortConnectSource(inputPort, source.endpoint, nil) == noErr else {
            throw ConnectError.cannotConnectToSource
        }
        
        preferredSourceID = source.id
        connectedSource = source
    }
    
    /// Connects to the first available MIDI input source.
    ///
    /// Use connect(to:) when the person should choose the source.
    public func connectToFirstAvailableSource() throws {
        guard let source = availableSources.first else { throw ConnectError.noSource }
        try connect(to: source)
    }
    
    /// Disconnects the current source and prevents it from being reconnected automatically.
    public func disconnect() {
        disconnect(preservingPreferredSource: false)
    }
    
    /// Creates an independent stream of events received from the connected source.
    ///
    /// Each stream retains at most 256 pending events. Slow consumers receive the newest
    /// events, while the Core MIDI receive thread remains unblocked.
    public func events() -> AsyncStream<MIDIInputEvent> {
        let identifier = UUID()
        
        return AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            eventContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.eventContinuations.removeValue(forKey: identifier)
                }
            }
        }
    }
    
    
    /// Publishes an event that has safely crossed from Core MIDI onto the main actor.
    private func publish(_ event: MIDIInputEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }
    
    /// Responds to MIDI setup changes without retaining Core MIDI callback memory.
    private func handle(messageID: MIDINotificationMessageID, changedEndpoint: MIDIEndpointRef?) {
        switch messageID {
        case .msgObjectRemoved:
            refreshAvailableSources()
            
            guard changedEndpoint == connectedSource?.endpoint else { return }
            disconnect(preservingPreferredSource: true)
        case .msgObjectAdded:
            refreshAvailableSources()
            reconnectIfPossible()
            connectToAddedSourceIfPossible(changedEndpoint)
        case .msgSetupChanged, .msgPropertyChanged:
            refreshAvailableSources()
            reconnectIfPossible()
        default:
            break
        }
    }
    
    /// Connects to a newly added input source when no source is currently connected.
    private func connectToAddedSourceIfPossible(_ endpoint: MIDIEndpointRef?) {
        guard connectedSource == nil,
              let endpoint,
              let source = availableSources.first(where: { $0.endpoint == endpoint }) else {
            return
        }
        
        do {
            try connect(to: source)
        } catch {
            logger.error("Failed to connect to newly added MIDI source: \(error.localizedDescription)")
        }
    }
    
    /// Reconnects to the preferred source when automatic reconnection is enabled.
    private func reconnectIfPossible() {
        guard automaticallyReconnect, connectedSource == nil,
              let preferredSourceID,
              let source = availableSources.first(where: { $0.id == preferredSourceID }) else {
            return
        }
        
        do {
            try connect(to: source)
        } catch {
            logger.error("Failed to reconnect to MIDI source: \(error.localizedDescription)")
        }
    }
    
    /// Disconnects the port while optionally retaining the source to reconnect later.
    private func disconnect(preservingPreferredSource: Bool) {
        if !preservingPreferredSource {
            preferredSourceID = nil
        }
        
        guard let connectedSource else { return }
        MIDIPortDisconnectSource(inputPort, connectedSource.endpoint)
        self.connectedSource = nil
    }
    
    
    /// A selectable Core MIDI input endpoint.
    public struct Source: Identifiable, Equatable {
        
        /// A stable Core MIDI identifier for this source.
        public let id: MIDIUniqueID
        
        /// The source’s display name.
        public let name: String
        
        /// The source manufacturer, when Core MIDI provides one.
        public let manufacturer: String?
        
        fileprivate let endpoint: MIDIEndpointRef
        
        
        fileprivate init?(_ endpoint: MIDIEndpointRef) {
            var isOffline: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &isOffline)
            guard isOffline == 0 else { return nil }
            
            var uniqueID = MIDIUniqueID()
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr else {
                return nil
            }
            
            self.endpoint = endpoint
            self.id = uniqueID
            self.name = MIDIObjectGetString(endpoint, kMIDIPropertyName) ?? "MIDI Source \(endpoint)"
            self.manufacturer = MIDIObjectGetString(endpoint, kMIDIPropertyManufacturer)
        }
    }
    
    
    /// Errors that can occur while creating or connecting the Core MIDI input port.
    public enum ConnectError: LocalizableError {
        case noSource
        case cannotCreateInputPort
        case cannotCreateClient
        case cannotConnectToSource
        
        /// A localized title appropriate for displaying the error.
        public var titleResource: LocalizedStringResource {
            "MIDI Input Connection Error"
        }
        
        /// A localized explanation appropriate for displaying the error.
        public var messageResource: LocalizedStringResource {
            switch self {
            case .noSource:
                "No MIDI input source found."
            case .cannotCreateInputPort:
                "Cannot create MIDI input port. Please restart the app."
            case .cannotCreateClient:
                "Cannot create MIDI client. Please restart the app."
            case .cannotConnectToSource:
                "Failed to connect to the selected MIDI input source."
            }
        }
    }
}


/// A timestamped Universal MIDI Packet received from a MIDI input source.
public struct MIDIInputEvent: @unchecked Sendable {
    
    /// The Core MIDI host-time timestamp for the message.
    public let timestamp: MIDITimeStamp
    
    /// The Universal MIDI Packet delivered by Core MIDI.
    public let message: MIDIUniversalMessage
    
    
    /// Creates an event from one Core MIDI message.
    public init(timestamp: MIDITimeStamp, message: MIDIUniversalMessage) {
        self.timestamp = timestamp
        self.message = message
    }
}


fileprivate func MIDIObjectGetString(_ object: MIDIObjectRef, _ propertyID: CFString) -> String? {
    var value: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(object, propertyID, &value) == noErr,
          let value else {
        return nil
    }
    return value.takeUnretainedValue() as String
}

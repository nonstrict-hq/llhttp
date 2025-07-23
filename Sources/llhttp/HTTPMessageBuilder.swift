//
//  HTTPMessageBuilder.swift
//  llhttp
//
//  Created by Mathijs Kadijk on 30/07/2025.
//

import Foundation

public protocol AnyHTTPMessageBuilder {
    var type: LLHTTP.Mode { get }
    var headerValues: [LLHTTP.PayloadType: [Data]] { get }
    var chunkValues: [[LLHTTP.PayloadType: [Data]]] { get }
}

internal struct HTTPMessageBuilder: AnyHTTPMessageBuilder {
    private(set) var type: LLHTTP.Mode = .both
    private(set) var headerValues: [LLHTTP.PayloadType: [Data]] = [:]
    private(set) var chunkValues: [[LLHTTP.PayloadType: [Data]]] = [[:]]

    mutating func append(_ payload: LLHTTP.Payload, state: LLHTTP.State) {
        type = state.type

        switch payload.type {
        case .url, .method, .protocol, .version, .status, .headerField, .headerValue:
            headerValues[payload.type, default: [Data()]][.last]?.append(payload.data)
        case .chunkExtensionName, .chunkExtensionValue, .body:
            chunkValues[.last]?[payload.type, default: [Data()]][.last]?.append(payload.data)
        }
    }

    mutating func append<MessageType: HTTPMessageType>(_ signal: LLHTTP.Signal, state: LLHTTP.State) -> MessageType? {
        type = state.type

        switch signal {
        case .messageBegin:
            break
        case .messageComplete:
            return MessageType(builder: self) // TODO: I don't like that this returning nil isn't distinguishable from nil because the message isn't complete yet
        case .reset:
            self = HTTPMessageBuilder()
        case .urlComplete:
            complete(.url)
        case .methodComplete:
            complete(.method)
        case .protocolComplete:
            complete(.protocol)
        case .versionComplete:
            complete(.version)
        case .statusComplete:
            complete(.status)
        case .headerFieldComplete:
            complete(.headerField)
        case .headerValueComplete:
            complete(.headerValue)
        case .chunkHeader:
            break
        case .chunkComplete:
            chunkValues.append([:])
        case .chunkExtensionNameComplete:
            complete(.chunkExtensionName)
        case .chunkExtensionValueComplete:
            complete(.chunkExtensionValue)
        }

        return nil
    }

    private mutating func complete(_ payloadType: LLHTTP.PayloadType) {
        switch payloadType {
        case .url, .method, .protocol, .version, .status, .headerField, .headerValue:
            headerValues[payloadType, default: [Data()]].append(Data())
        case .chunkExtensionName, .chunkExtensionValue:
            chunkValues[.last]?[payloadType, default: [Data()]].append(Data())
        case .body:
            assertionFailure("Body can't be completed, that would be chunk completed")
            break
        }
    }
}

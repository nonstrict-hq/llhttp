//
//  LLHTTP+Events.swift
//  llhttp
//
//  Created by Mathijs Kadijk on 23/07/2025.
//

import Foundation

extension LLHTTP {
    /// Events that don't carry data payloads
    public enum Signal: Sendable {
        /// Invoked when a new request/response starts
        case messageBegin

        /// Invoked when a request/response has been completely parsed
        case messageComplete

        /// Invoked after `messageComplete` and before `messageBegin` when a new message
        /// is received on the same parser. This is not invoked for the first message
        case reset

        /// Invoked after the URL has been parsed
        case urlComplete

        /// Invoked after the HTTP method has been parsed
        case methodComplete

        /// Invoked after the protocol has been parsed
        case protocolComplete

        /// Invoked after the HTTP version has been parsed
        case versionComplete

        /// Invoked after the status code has been parsed
        case statusComplete

        /// Invoked after a header name has been parsed
        case headerFieldComplete

        /// Invoked after a header value has been parsed
        case headerValueComplete

        /// Invoked after a new chunk is started
        /// The current chunk length is available in the parser's content length
        case chunkHeader

        /// Invoked after a new chunk is received
        case chunkComplete

        /// Invoked after a chunk extension name is parsed
        case chunkExtensionNameComplete

        /// Invoked after a chunk extension value is parsed
        case chunkExtensionValueComplete
    }

    /// Event that carries a data payload
    public struct Payload: Sendable {
        public let type: PayloadType
        public let data: Data
    }

    /// Types of data events
    public enum PayloadType: Sendable {
        /// Invoked when another character of the URL is received
        case url

        /// Invoked when another character of the method is received
        /// When parser is created with `HTTP_BOTH` and the input is a response,
        /// this is also invoked for the sequence `HTTP/` of the first message
        case method

        /// Invoked when another character of the protocol is received
        case `protocol`

        /// Invoked when another character of the version is received
        case version

        /// Invoked when another character of the status is received
        case status

        /// Invoked when another character of a header name is received
        case headerField

        /// Invoked when another character of a header value is received
        case headerValue

        /// Invoked when another character of the body is received
        case body

        /// Invoked when another character of a chunk extension name is received
        case chunkExtensionName

        /// Invoked when another character of a chunk extension value is received
        case chunkExtensionValue
    }

    /// Return values for signal events (no data)
    public enum SignalAction: Int32, Sendable {
        /// Proceed normally
        case proceed = 0

        /// Error occurred
        case error = -1

        /// Pause the parser
        case pause = 21
    }

    /// Return values for payload event callbacks
    public enum PayloadAction: Int32, Sendable {
        /// Proceed normally
        case proceed = 0

        /// Error occurred
        case error = -1

        /// Error from the callback
        case userError = 24
    }

    /// Return values for the headers complete callback
    public enum HeadersCompleteAction: Int32, Sendable {
        /// Proceed normally
        case proceed = 0

        /// Assume that request/response has no body, and proceed to parsing the next message.
        /// This does NOT skip body bytes - it assumes no body exists at all.
        /// Use this for pipelined requests without bodies or when you know no body follows.
        case assumeNoBodyAndContinue = 1

        /// Assume absence of body and make `parse()` throw `HPE_PAUSED_UPGRADE`.
        /// Use this for handling protocol upgrades (e.g., WebSocket).
        case assumeNoBodyAndPauseUpgrade = 2

        /// Error occurred
        case error = -1

        /// Pause the parser
        case pause = 21
    }
}

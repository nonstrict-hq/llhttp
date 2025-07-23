//
//  LLHTTP+State.swift
//  llhttp
//
//  Created by Mathijs Kadijk on 24/07/2025.
//

import Foundation
internal import Cllhttp

extension LLHTTP {
    /// The current state of the parser.
    ///
    /// Represents the current parsing state and provides read-only access to
    /// various properties of the request or response being parsed.
    public struct State: Sendable {
        /// The type of the parser (request, response, or both).
        public let type: Mode

        /// The major version of the HTTP protocol of the current request/response.
        public let majorVersion: UInt8

        /// The minor version of the HTTP protocol of the current request/response.
        public let minorVersion: UInt8

        /// The HTTP method of the current request.
        ///
        /// Will be `nil` for responses.
        public let method: String?

        /// The status code of the current response.
        ///
        /// Will be `nil` for requests.
        public let statusCode: Int32?

        /// The textual name of the HTTP status.
        ///
        /// Will be `nil` for requests or if status code is invalid.
        public let statusName: String?

        /// Whether the request includes the `Connection: upgrade` header.
        public let upgrade: Bool

        /// The content length of the current message.
        ///
        /// This value is parsed from the Content-Length header when present will be zero if header isn't seen yet.
        public let contentLength: UInt64

        /// Whether there might be any other messages following the last that was successfully parsed.
        public let shouldKeepAlive: Bool

        /// Whether the incoming message is parsed until the last byte, and has to be completed by calling `finish()` on EOF.
        ///
        /// Requests without Content-Length and other messages might require treating all incoming
        /// bytes as the part of the body, up to the last byte of the connection.
        public let messageNeedsEOF: Bool
    }
}

internal extension LLHTTP.State {
    init(parser: UnsafeMutablePointer<llhttp_t>) {
        self.type = LLHTTP.Mode(rawValue: UInt32(llhttp_get_type(parser))) ?? .both
        self.majorVersion = llhttp_get_http_major(parser)
        self.minorVersion = llhttp_get_http_minor(parser)
        if type == .request, let methodName = llhttp_method_name(llhttp_method_t(rawValue: UInt32(llhttp_get_method(parser)))) {
            self.method = String(cString: methodName)
        } else {
            self.method = nil
        }
        let statusCode = llhttp_get_status_code(parser)
        if statusCode > 0 {
            self.statusCode = statusCode
            if let statusName = llhttp_status_name(llhttp_status_t(rawValue: UInt32(statusCode))) {
                self.statusName = String(cString: statusName)
            } else {
                self.statusName = nil
            }
        } else {
            self.statusCode = nil
            self.statusName = nil
        }
        self.upgrade = llhttp_get_upgrade(parser) == 1
        self.contentLength = parser.pointee.content_length
        self.shouldKeepAlive = llhttp_should_keep_alive(parser) == 1
        self.messageNeedsEOF = llhttp_message_needs_eof(parser) == 1
    }
}

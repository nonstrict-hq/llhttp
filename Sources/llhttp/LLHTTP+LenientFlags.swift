//
//  LLHTTP+LenientFlags.swift
//  llhttp
//
//  Created by Mathijs Kadijk on 23/07/2025.
//

import Foundation

extension LLHTTP {
    /// Options for enabling lenient parsing modes in llhttp.
    ///
    /// - Warning: Enabling lenient parsing flags can pose security risks including
    ///   request smuggling, cache poisoning, and other attacks. Use with extreme caution
    ///   and only when absolutely necessary for compatibility with non-compliant clients/servers.
    public struct LenientFlags: OptionSet, Sendable, CustomDebugStringConvertible {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Enables lenient header value parsing.
        ///
        /// When enabled, disables header value token checks, extending llhttp's protocol
        /// support to highly non-compliant clients/servers. No `HPE_INVALID_HEADER_TOKEN`
        /// will be raised for incorrect header values.
        ///
        /// - Warning: This can expose you to request smuggling attacks. USE WITH CAUTION!
        public static let headers = LenientFlags(rawValue: 1 << 0)

        /// Enables lenient handling of conflicting Transfer-Encoding and Content-Length headers.
        ///
        /// Normally llhttp would error when `Transfer-Encoding` is present in conjunction
        /// with `Content-Length`. This error is important to prevent HTTP request smuggling,
        /// but may be less desirable for small number of cases involving legacy servers.
        ///
        /// - Warning: This can expose you to request smuggling attacks. USE WITH CAUTION!
        public static let chunkedLength = LenientFlags(rawValue: 1 << 1)

        /// Enables lenient handling of Connection: close and HTTP/1.0 requests/responses.
        ///
        /// Normally llhttp would error the HTTP request/response after the request/response
        /// with `Connection: close` and `Content-Length`. This is important to prevent cache
        /// poisoning attacks, but might interact badly with outdated and insecure clients.
        /// With this flag the extra request/response will be parsed normally.
        ///
        /// - Warning: This can expose you to cache poisoning attacks. USE WITH CAUTION!
        public static let keepAlive = LenientFlags(rawValue: 1 << 2)

        /// Enables lenient handling of Transfer-Encoding header.
        ///
        /// Normally llhttp would error when a `Transfer-Encoding` has chunked value and
        /// another value after it (either in a single header or in multiple headers whose
        /// values are internally joined using `,`). This is mandated by the spec to reliably
        /// determine request body size and thus avoid request smuggling. With this flag
        /// the extra value will be parsed normally.
        ///
        /// - Warning: This can expose you to request smuggling attacks. USE WITH CAUTION!
        public static let transferEncoding = LenientFlags(rawValue: 1 << 3)

        /// Enables lenient handling of HTTP version.
        ///
        /// Normally llhttp would error when the HTTP version in the request or status line
        /// is not 0.9, 1.0, 1.1 or 2.0. With this flag the extra value will be parsed normally.
        ///
        /// - Warning: This allows unsupported HTTP versions. USE WITH CAUTION!
        public static let version = LenientFlags(rawValue: 1 << 4)

        /// Enables lenient handling of additional data received after a message ends
        /// and keep-alive is disabled.
        ///
        /// Normally llhttp would error when additional unexpected data is received if the
        /// message contains the Connection header with close value. With this flag the
        /// extra data will be discarded without throwing an error.
        ///
        /// - Warning: This can expose you to poisoning attacks. USE WITH CAUTION!
        public static let dataAfterClose = LenientFlags(rawValue: 1 << 5)

        /// Enables lenient handling of incomplete CRLF sequences.
        ///
        /// Normally llhttp would error when a CR is not followed by LF when terminating
        /// the request line, the status line, the headers or a chunk header. With this
        /// flag only a CR is required to terminate such sections.
        ///
        /// - Warning: This can expose you to request smuggling attacks. USE WITH CAUTION!
        public static let optionalLFAfterCR = LenientFlags(rawValue: 1 << 6)

        /// Enables lenient handling of line separators.
        ///
        /// Normally llhttp would error when a LF is not preceded by CR when terminating
        /// the request line, the status line, the headers, a chunk header or chunk data.
        /// With this flag only a LF is required to terminate such sections.
        ///
        /// - Warning: This can expose you to request smuggling attacks. USE WITH CAUTION!
        public static let optionalCRBeforeLF = LenientFlags(rawValue: 1 << 7)

        /// Enables lenient handling of chunks not separated via CRLF.
        ///
        /// Normally llhttp would error when after chunk data a CRLF is missing before
        /// starting a new chunk. With this flag the new chunk can start immediately
        /// after the previous one.
        ///
        /// - Warning: This can expose you to request smuggling attacks. USE WITH CAUTION!
        public static let optionalCRLFAfterChunk = LenientFlags(rawValue: 1 << 8)

        /// Enables lenient handling of spaces after chunk size.
        ///
        /// Normally llhttp would error when a chunk size is followed by one or more
        /// spaces instead of a CRLF or `;`. With this flag this check is disabled.
        ///
        /// - Warning: This can expose you to request smuggling attacks. USE WITH CAUTION!
        public static let spacesAfterChunkSize = LenientFlags(rawValue: 1 << 9)

        /// All lenient flags enabled.
        ///
        /// - Warning: Enabling all lenient flags significantly weakens HTTP parsing
        ///   security. This should only be used in extremely controlled environments
        ///   where security is not a concern. USE WITH EXTREME CAUTION!
        public static let all: LenientFlags = [
            .headers,
            .chunkedLength,
            .keepAlive,
            .transferEncoding,
            .version,
            .dataAfterClose,
            .optionalLFAfterCR,
            .optionalCRBeforeLF,
            .optionalCRLFAfterChunk,
            .spacesAfterChunkSize
        ]

        public var debugDescription: String {
            var flags: [String] = []

            if contains(.headers) { flags.append("headers") }
            if contains(.chunkedLength) { flags.append("chunkedLength") }
            if contains(.keepAlive) { flags.append("keepAlive") }
            if contains(.transferEncoding) { flags.append("transferEncoding") }
            if contains(.version) { flags.append("version") }
            if contains(.dataAfterClose) { flags.append("dataAfterClose") }
            if contains(.optionalLFAfterCR) { flags.append("optionalLFAfterCR") }
            if contains(.optionalCRBeforeLF) { flags.append("optionalCRBeforeLF") }
            if contains(.optionalCRLFAfterChunk) { flags.append("optionalCRLFAfterChunk") }
            if contains(.spacesAfterChunkSize) { flags.append("spacesAfterChunkSize") }

            if flags.isEmpty {
                return "LLHTTP.LenientFlags(none)"
            } else {
                return "LLHTTP.LenientFlags[\(flags.joined(separator: ", "))]"
            }
        }
    }
}

//
//  LLHTTP+Preconcurrency.swift
//  llhttp
//
//  Created by Mathijs Kadijk on 27/07/2025.
//

import Foundation
internal import Cllhttp

extension LLHTTP {

    /// An HTTP/1.x parser that processes messages incrementally through callbacks.
    ///
    /// LLHTTP wraps the llhttp C library to provide event-driven parsing of HTTP messages through
    /// callbacks. It supports incremental parsing, allowing you to feed data as it arrives from
    /// the network without buffering entire messages.
    ///
    /// Initialize the parser with a parsing mode, optionally configure callbacks with `setCallbacks(_:)`,
    /// then call `parse(_:)` with incoming data. If no callbacks are set, the parser will use default
    /// handlers that return `.proceed` for all events. The parser maintains state across calls,
    /// accumulating a complete HTTP message.
    ///
    /// - Warning: This class is non-sendable and non-reentrant - methods cannot be called recursively
    ///   or from within their own callbacks and you should not call it concurrently from different
    ///   isolation domains.
    public class Preconcurrency {
        public typealias SignalHandler = (Signal, State) -> SignalAction
        public typealias PayloadHandler = (Payload, State) -> PayloadAction
        public typealias HeadersCompleteHandler = (State) -> HeadersCompleteAction

        internal class Callbacks {
            var signalHandler: SignalHandler = { _, _ in .proceed }
            var payloadHandler: PayloadHandler = { _, _ in .proceed }
            var headersCompleteHandler: HeadersCompleteHandler = { _ in .proceed }
        }

        private var parser = llhttp_t()
        private var settings = llhttp_settings_t()
        private let callbacks: Callbacks

        /// Options for enabling lenient parsing modes in llhttp.
        ///
        /// - Warning: Enabling lenient parsing flags can pose security risks including
        ///   request smuggling, cache poisoning, and other attacks. Use with extreme caution
        ///   and only when absolutely necessary for compatibility with non-compliant clients/servers.
        public var lenientFlags = LenientFlags() {
            didSet {
                withUnsafeMutablePointer(to: &parser) { parser in
                    llhttp_set_lenient_headers(parser, lenientFlags.contains(.headers) ? 1 : 0)
                    llhttp_set_lenient_chunked_length(parser, lenientFlags.contains(.chunkedLength) ? 1 : 0)
                    llhttp_set_lenient_keep_alive(parser, lenientFlags.contains(.keepAlive) ? 1 : 0)
                    llhttp_set_lenient_transfer_encoding(parser, lenientFlags.contains(.transferEncoding) ? 1 : 0)
                    llhttp_set_lenient_version(parser, lenientFlags.contains(.version) ? 1 : 0)
                    llhttp_set_lenient_data_after_close(parser, lenientFlags.contains(.dataAfterClose) ? 1 : 0)
                    llhttp_set_lenient_optional_lf_after_cr(parser, lenientFlags.contains(.optionalLFAfterCR) ? 1 : 0)
                    llhttp_set_lenient_optional_crlf_after_chunk(parser, lenientFlags.contains(.optionalCRLFAfterChunk) ? 1 : 0)
                    llhttp_set_lenient_optional_cr_before_lf(parser, lenientFlags.contains(.optionalCRBeforeLF) ? 1 : 0)
                    llhttp_set_lenient_spaces_after_chunk_size(parser, lenientFlags.contains(.spacesAfterChunkSize) ? 1 : 0)
                }
            }
        }

        /// The current state of the parser.
        ///
        /// Represents the current parsing state and provides read-only access to
        /// various properties of the request or response being parsed.
        public var state: State { withUnsafeMutablePointer(to: &parser, State.init) }

        /// Configure callback handlers for processing HTTP message events.
        ///
        /// Use this method to set up custom handlers for different parsing events. If not called,
        /// the parser will use default handlers that return `.proceed` for all events, allowing
        /// basic parsing without custom event handling.
        ///
        /// - Parameters:
        ///   - signalHandler: Handles parsing events (message boundaries, completion signals).
        ///     Default returns `.proceed` for all signals.
        ///   - payloadHandler: Receives data fragments (URLs, headers, body). Data may arrive in
        ///     chunks - accumulate until the corresponding complete signal. Default returns `.proceed`.
        ///   - headersCompleteHandler: Called after all headers are parsed. Return `.assumeNoBodyAndContinue`
        ///     to tell the parser that no body exists and to immediately parse the next message (useful for
        ///     pipelined requests without bodies). Return `.assumeNoBodyAndPauseUpgrade` for protocol upgrades.
        ///     Note: These options do NOT skip body bytes - they assume no body exists at all.
        ///     Default returns `.proceed`.
        ///
        /// - Note: Handlers control parser flow by returning actions: `.proceed` continues parsing,
        ///   `.pause` temporarily halts (resumable via `resume()`), `.error` aborts with an error.
        ///
        /// - Important: The parser retains references to all handlers throughout its lifetime. Handlers
        ///   are invoked synchronously during `parse(_:)` calls, so avoid blocking operations.
        public func setCallbacks(signalHandler: @escaping SignalHandler = { _, _ in .proceed },
                                 payloadHandler: @escaping PayloadHandler = { _, _ in .proceed },
                                 headersCompleteHandler: @escaping HeadersCompleteHandler = { _ in .proceed }) {
            callbacks.signalHandler = signalHandler
            callbacks.payloadHandler = payloadHandler
            callbacks.headersCompleteHandler = headersCompleteHandler
        }

        /// Initializes an HTTP parser for processing HTTP messages.
        ///
        /// Creates a new parser instance configured for the specified parsing mode. The parser
        /// starts with default callback handlers that return `.proceed` for all events. Use
        /// `setCallbacks(_:)` to configure custom event handlers after initialization.
        ///
        /// - Parameters:
        ///   - mode: Whether to parse HTTP requests, responses or should detect it based on the first message.
        public init(mode: Mode) {
            self.callbacks = Callbacks()

            var parser = llhttp_t()
            let callbacks = Unmanaged.passRetained(callbacks)
            withUnsafeMutablePointer(to: &settings) { settings in
                llhttp_settings_init(settings)

                // Simple callbacks (llhttp_cb)
                settings.pointee.on_message_begin = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.messageBegin, State(parser: parser)).rawValue
                }

                settings.pointee.on_headers_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.headersCompleteHandler(State(parser: parser)).rawValue
                }

                settings.pointee.on_message_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.messageComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_protocol_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.protocolComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_url_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.urlComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_status_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.statusComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_method_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.methodComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_version_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.versionComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_header_field_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.headerFieldComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_header_value_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.headerValueComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_chunk_extension_name_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.chunkExtensionNameComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_chunk_extension_value_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.chunkExtensionValueComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_chunk_header = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.chunkHeader, State(parser: parser)).rawValue
                }

                settings.pointee.on_chunk_complete = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.chunkComplete, State(parser: parser)).rawValue
                }

                settings.pointee.on_reset = { parser in
                    guard let parser else { return SignalAction.error.rawValue }
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.signalHandler(.reset, State(parser: parser)).rawValue
                }

                settings.pointee.on_protocol = { parser, at, length in
                    guard let parser, let at else { return SignalAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .protocol, data: data), State(parser: parser)).rawValue
                }

                settings.pointee.on_url = { parser, at, length in
                    guard let parser, let at else { return PayloadAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .url, data: data), State(parser: parser)).rawValue
                }

                settings.pointee.on_status = { parser, at, length in
                    guard let parser, let at else { return PayloadAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .status, data: data), State(parser: parser)).rawValue
                }

                settings.pointee.on_method = { parser, at, length in
                    guard let parser, let at else { return PayloadAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .method, data: data), State(parser: parser)).rawValue
                }

                settings.pointee.on_version = { parser, at, length in
                    guard let parser, let at else { return PayloadAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .version, data: data), State(parser: parser)).rawValue
                }

                settings.pointee.on_header_field = { parser, at, length in
                    guard let parser, let at else { return PayloadAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .headerField, data: data), State(parser: parser)).rawValue
                }

                settings.pointee.on_header_value = { parser, at, length in
                    guard let parser, let at else { return PayloadAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .headerValue, data: data), State(parser: parser)).rawValue
                }

                settings.pointee.on_chunk_extension_name = { parser, at, length in
                    guard let parser, let at else { return PayloadAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .chunkExtensionName, data: data), State(parser: parser)).rawValue
                }

                settings.pointee.on_chunk_extension_value = { parser, at, length in
                    guard let parser, let at else { return PayloadAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .chunkExtensionValue, data: data), State(parser: parser)).rawValue
                }

                settings.pointee.on_body = { parser, at, length in
                    guard let parser, let at else { return PayloadAction.error.rawValue }
                    let data = Data(bytes: at, count: length)
                    let callbacks = Unmanaged<Callbacks>.fromOpaque(parser.pointee.data).takeUnretainedValue()
                    return callbacks.payloadHandler(Payload(type: .body, data: data), State(parser: parser)).rawValue
                }

                withUnsafeMutablePointer(to: &parser) { parser in
                    llhttp_init(parser, mode.type, settings)
                    parser.pointee.data = callbacks.toOpaque()
                }
            }
            self.parser = parser
        }

        /// Parse full or partial HTTP request/response data.
        ///
        /// Processes the provided data through the configured callbacks (or default handlers if none are set).
        /// If any callback returns an error, parsing interrupts and this method rethrows the callback error.
        ///
        /// If `HPE_PAUSED` is thrown, execution can be resumed by calling `resume()`. In that case the input
        /// should be advanced to the last processed byte from the parser, which can be obtained via
        /// `llhttp_get_error_pos()`.
        ///
        /// In a special case of CONNECT/Upgrade request/response `HPE_PAUSED_UPGRADE` is thrown after fully
        /// parsing the request/response. If you wish to continue parsing, invoke `resumeAfterUpgrade()`.
        ///
        /// - Parameters:
        ///   - data: The HTTP data to parse (can be partial)
        ///
        /// - Throws: `LLHTTPError` for parsing errors or callback-initiated errors
        ///
        /// - Note: Once this throws a non-pause type error, it will continue to return the same error
        ///   upon each successive call until you call `reset()`.
        public func parse(_ data: Data) throws {
            let errorNo = withUnsafeMutablePointer(to: &parser) { parser in
                data.withUnsafeBytes { data in
                    llhttp_execute(parser, data.bindMemory(to: CChar.self).baseAddress, data.count)
                }
            }

            guard errorNo == HPE_OK else {
                let name = String(cString: llhttp_errno_name(errorNo))
                let reason = llhttp_get_error_reason(&parser).map(String.init(cString:))
                throw LLHTTPError(code: errorNo.rawValue, name: name, reason: reason)
            }
        }

        /// Make further calls of `parse()` throw the `HPE_PAUSED` error and set appropriate error reason.
        public func pause() {
            withUnsafeMutablePointer(to: &parser, llhttp_pause)
        }

        /// Might be called to resume the execution after the pausing through the callback or after manually calling pause.
        public func resume() {
            withUnsafeMutablePointer(to: &parser, llhttp_resume)
        }

        /// Might be called to resume the execution after the `HPE_PAUSED_UPGRADE` error was thrown.
        public func resumeAfterUpgrade() {
            withUnsafeMutablePointer(to: &parser, llhttp_resume_after_upgrade)
        }

        /// This method should be called when the other side has no further bytes to send (e.g. shutdown of readable side of the TCP connection.)
        ///
        /// Requests without Content-Length and other messages might require treating all incoming bytes as the part of the body, up to the last byte of the connection.
        ///
        /// This method will yield if the request was terminated safely. Otherwise an error code would be returned.
        public func finish() throws {
            let errorNo = withUnsafeMutablePointer(to: &parser, llhttp_finish)

            guard errorNo == HPE_OK else {
                let name = String(cString: llhttp_errno_name(errorNo))
                let reason = String(cString: llhttp_get_error_reason(&parser))
                throw LLHTTPError(code: errorNo.rawValue, name: name, reason: reason)
            }
        }

        /// Reset the parser back to the start state, preserving the existing mode, callbacks, and lenient flags.
        public func reset() {
            withUnsafeMutablePointer(to: &parser, llhttp_reset)
        }
    }
}

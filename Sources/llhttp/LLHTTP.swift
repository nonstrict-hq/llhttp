//
//  LLHTTP.swift
//  llhttp
//
//  Created by Nonstrict on 23/07/2025.
//

import Foundation

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
/// - Note: This is an actor type, ensuring thread-safe access to the parser state.
public actor LLHTTP {
    public typealias SignalHandler = @Sendable (Signal, State) -> SignalAction
    public typealias PayloadHandler = @Sendable (Payload, State) -> PayloadAction
    public typealias HeadersCompleteHandler = @Sendable (State) -> HeadersCompleteAction

    internal let preconcurrency: Preconcurrency

    /// Options for enabling lenient parsing modes in llhttp.
    ///
    /// - Warning: Enabling lenient parsing flags can pose security risks including
    ///   request smuggling, cache poisoning, and other attacks. Use with extreme caution
    ///   and only when absolutely necessary for compatibility with non-compliant clients/servers.
    public var lenientFlags: LenientFlags { preconcurrency.lenientFlags }

    /// Options for enabling lenient parsing modes in llhttp.
    ///
    /// - Warning: Enabling lenient parsing flags can pose security risks including
    ///   request smuggling, cache poisoning, and other attacks. Use with extreme caution
    ///   and only when absolutely necessary for compatibility with non-compliant clients/servers.
    public func setLenientFlags(_ flags: LenientFlags) {
        preconcurrency.lenientFlags = flags
    }

    /// The current state of the parser.
    ///
    /// Represents the current parsing state and provides read-only access to
    /// various properties of the request or response being parsed.
    public var state: State { preconcurrency.state }

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
    ///   are invoked synchronously during `parse(_:)` calls, so avoid blocking operations or use
    ///   actor isolation appropriately.
    public func setCallbacks(signalHandler: @escaping SignalHandler = { _, _ in .proceed },
                             payloadHandler: @escaping PayloadHandler = { _, _ in .proceed },
                             headersCompleteHandler: @escaping HeadersCompleteHandler = { _ in .proceed }) {
        preconcurrency.setCallbacks(signalHandler: signalHandler, payloadHandler: payloadHandler, headersCompleteHandler: headersCompleteHandler)
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
        preconcurrency = .init(mode: mode)
    }

    internal init(llhttp: LLHTTP.Preconcurrency) {
        preconcurrency = llhttp
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
        try preconcurrency.parse(data)
    }

    /// Make further calls of `parse()` throw the `HPE_PAUSED` error and set appropriate error reason.
    public func pause() {
        preconcurrency.pause()
    }

    /// Might be called to resume the execution after the pausing through the callback or after manually calling pause.
    public func resume() {
        preconcurrency.resume()
    }

    /// Might be called to resume the execution after the `HPE_PAUSED_UPGRADE` error was thrown.
    public func resumeAfterUpgrade() {
        preconcurrency.resumeAfterUpgrade()
    }

    /// This method should be called when the other side has no further bytes to send (e.g. shutdown of readable side of the TCP connection.)
    ///
    /// Requests without Content-Length and other messages might require treating all incoming bytes as the part of the body, up to the last byte of the connection.
    ///
    /// This method will trigger the calbacks if the request was terminated safely. Otherwise a error code would be returned.
    public func finish() throws {
        try preconcurrency.finish()
    }

    /// Reset the parser back to the start state, preserving the existing mode, callbacks, and lenient flags.
    public func reset() {
        preconcurrency.reset()
    }
}

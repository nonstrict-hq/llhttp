//
//  HTTPMessagesParser.swift
//  llhttp
//
//  Created by Mathijs Kadijk on 27/07/2025.
//

import Foundation
import os

/// HTTP Message parser that returns complete HTTP messages.
///
/// Pass in (partial) data of HTTP messages and this parser will either give you the fuly parsed HTTP
/// request/responses or throw an error if the message wasn't valid. Uses llhttp under the hood that you can
/// access and modify as required.
///
/// - Note: This is an actor type, ensuring thread-safe access to the parser state.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public actor HTTPMessagesParser<MessageType: HTTPMessageType> {
    /// Whether to pause the parser or not after this message.
    public enum MessageHandlerAction: Sendable {
        /// Pause the parser.
        ///
        /// Calls to `parse()` will throw paused errors until llhttp is resumed.
        case pause

        /// Proceed to the next message normally.
        case proceed
    }

    private struct State {
        var builder = HTTPMessageBuilder()
        var messageHandler: @Sendable (MessageType) throws -> MessageHandlerAction = { _ in .proceed }
    }

    private nonisolated let state = OSAllocatedUnfairLock(initialState: State())

    /// Underlying LLHTTP parser that is used.
    ///
    /// Can freely be configured and called to setup custom behaviour.
    /// For example to set lenient flags, add custom callbacks or resume parsing.
    public let llhttp: LLHTTP

    /// An async stream of all completed HTTP messages.
    ///
    /// Gives exactly the same messages as `messageHandler`, but might be more convenient to use in come situations.
    public let completedMessages: AsyncStream<MessageType>

    /// Callback that receives all completed HTTP messages, can pause the parser with it's return value.
    ///
    /// Gives exactly the same messages as `completedMessages`, but gives control to pause parsing.
    public nonisolated var messageHandler: @Sendable (MessageType) throws -> MessageHandlerAction {
        get { state.withLock { $0.messageHandler } }
        set { state.withLock { $0.messageHandler = newValue } }
    }

    /// Initialized the parser to parse complete HTTP messages of the inferred type.
    public init() async {
        await self.init(mode: MessageType.self)
    }
    
    /// Initialized the parser to parse complete HTTP messages of the given type.
    ///
    /// - Parameter mode: The type of message to parse, for example: `HTTPMessage.Request.self`, `HTTPMessage.Respone.self` or `HTTPMessage.Both.self`
    public init(mode: MessageType.Type) async {
        let (stream, continuation) = AsyncStream<MessageType>.makeStream(bufferingPolicy: .unbounded)
        completedMessages = stream

        llhttp = LLHTTP(llhttp: LLHTTPPreconcurrencyProxy(mode: MessageType.mode))
        await llhttp.setInternalCallbacks { [weak self] signal, state in
            guard let self else { return .error }

            let message: MessageType? = self.state.withLock { $0.builder.append(signal, state: state) }
            guard let message else { return .proceed }

            do {
                continuation.yield(message)
                let messageHandlerAction = try self.state.withLock { try $0.messageHandler(message) }
                switch messageHandlerAction {
                case .pause:
                    return .pause
                case .proceed:
                    return .proceed
                }
            } catch {
                return .error
            }
        } payloadHandler: { [weak self] payload, state in
            guard let self else { return .error }
            self.state.withLock { $0.builder.append(payload, state: state) }
            return .proceed
        }
    }

    /// Parse full or partial HTTP request/response data.
    ///
    /// Processes the provided data and will emit any HTTP messages if completely parsed.
    /// If any callback returns an error, parsing interrupts and this method rethrows the callback error.
    ///
    /// - Parameters:
    ///   - data: The HTTP data to parse (can be partial)
    ///
    /// - Throws: `LLHTTPError` for parsing errors or callback-initiated errors
    ///
    /// - Note: Once this throws a non-pause type error, it will continue to return the same error
    ///   upon each successive call until you call `reset()` on `llhttp`.
    public func parse(_ data: Data) async throws {
        try await llhttp.parse(data)
    }

    /// This method should be called when the other side has no further bytes to send (e.g. shutdown of readable side of the TCP connection.)
    ///
    /// Requests without Content-Length and other messages might require treating all incoming bytes as the part of the body, up to the last byte of the connection.
    ///
    /// This method will yield to the async stream if the request was terminated safely. Otherwise a error code would be returned.
    public func finish() async throws {
        try await llhttp.finish()
    }

    /// HTTP Message parser that returns complete HTTP messages.
    ///
    /// Pass in (partial) data of HTTP messages and this parser will either give you the fuly parsed HTTP
    /// request/responses or throw an error if the message wasn't valid. Uses llhttp under the hood that you can
    /// access and modify as required.
    ///
    /// - Warning: This class is non-sendable and non-reentrant - methods cannot be called recursively
    ///   or from within their own callbacks and you should not call it concurrently from different
    ///   isolation domains.
    public class Preconcurrency {
        private var builder: HTTPMessageBuilder

        /// Underlying LLHTTP parser that is used.
        ///
        /// Can freely be configured and called to setup custom behaviour.
        /// For example to set lenient flags, add custom callbacks or resume parsing.
        public let llhttp: LLHTTP.Preconcurrency

        /// Callback that receives all completed HTTP messages, can pause the parser with it's return value.
        public var messageHandler: (MessageType) throws -> MessageHandlerAction = { _ in .proceed }

        /// Initialized the parser to parse complete HTTP messages of the inferred type.
        public convenience init() {
            self.init(mode: MessageType.self)
        }

        /// Initialized the parser to parse complete HTTP messages of the given type.
        ///
        /// - Parameter mode: The type of message to parse, for example: `HTTPMessage.Request.self`, `HTTPMessage.Respone.self` or `HTTPMessage.Both.self`
        public init(mode: MessageType.Type) {
            builder = HTTPMessageBuilder()
            let llhttpProxy = LLHTTPPreconcurrencyProxy(mode: MessageType.mode)
            llhttp = llhttpProxy
            llhttpProxy.setInternalCallbacks { [weak self] signal, state in
                guard let self else { return .error }
                guard let message: MessageType = self.builder.append(signal, state: state) else { return .proceed }

                do {
                    let messageHandlerAction = try messageHandler(message)
                    switch messageHandlerAction {
                    case .pause:
                        return .pause
                    case .proceed:
                        return .proceed
                    }
                } catch {
                    return .error
                }
            } payloadHandler: { [weak self] payload, state in
                guard let self else { return .error }

                self.builder.append(payload, state: state)
                return .proceed
            }
        }

        /// Parse full or partial HTTP request/response data.
        ///
        /// Processes the provided data and will emit any HTTP messages if completely parsed.
        /// If any callback returns an error, parsing interrupts and this method rethrows the callback error.
        ///
        /// - Parameters:
        ///   - data: The HTTP data to parse (can be partial)
        ///
        /// - Throws: `LLHTTPError` for parsing errors or callback-initiated errors
        ///
        /// - Note: Once this throws a non-pause type error, it will continue to return the same error
        ///   upon each successive call until you call `reset()` on `llhttp`.
        public func parse(_ data: Data) throws {
            try llhttp.parse(data)
        }

        /// This method should be called when the other side has no further bytes to send (e.g. shutdown of readable side of the TCP connection.)
        ///
        /// Requests without Content-Length and other messages might require treating all incoming bytes as the part of the body, up to the last byte of the connection.
        ///
        /// This method will trigger the callback if the request was terminated safely. Otherwise a error code would be returned.
        public func finish() async throws {
            try llhttp.finish()
        }
    }
}

internal class LLHTTPPreconcurrencyProxy: LLHTTP.Preconcurrency {
    private let internalCallbacks: Callbacks = .init()

    public override init(mode: LLHTTP.Mode) {
        super.init(mode: mode)
        setCallbacks() // Makes sure the internal callback will be fired, even if the user doesn't set it's own callbacks
    }

    internal func setInternalCallbacks(signalHandler: @escaping SignalHandler = { _, _ in .proceed },
                                       payloadHandler: @escaping PayloadHandler = { _, _ in .proceed },
                                       headersCompleteHandler: @escaping HeadersCompleteHandler = { _ in .proceed }) {
        internalCallbacks.signalHandler = signalHandler
        internalCallbacks.payloadHandler = payloadHandler
        internalCallbacks.headersCompleteHandler = headersCompleteHandler
    }

    public override func setCallbacks(signalHandler: LLHTTP.Preconcurrency.SignalHandler? = nil,
                                      payloadHandler: LLHTTP.Preconcurrency.PayloadHandler? = nil,
                                      headersCompleteHandler: LLHTTP.Preconcurrency.HeadersCompleteHandler? = nil) {
        super.setCallbacks { [internalCallbacks] signal, state in
            let internalAction = internalCallbacks.signalHandler(signal, state)
            let userAction = signalHandler?(signal, state)
            switch (internalAction, userAction) {
            case (_, .none):
                return internalAction
            case (.proceed, .proceed):
                return .proceed
            case (.error, _), (_, .error):
                return .error
            case (.pause, _), (_, .pause):
                return .pause
            }
        } payloadHandler: { [internalCallbacks] payload, state in
            let internalAction = internalCallbacks.payloadHandler(payload, state)
            let userAction = payloadHandler?(payload, state)
            switch (internalAction, userAction) {
            case (_, .none):
                return internalAction
            case (.proceed, .proceed):
                return .proceed
            case (.error, _), (_, .error):
                return .error
            case (.userError, _), (_, .userError):
                return .userError
            }
        } headersCompleteHandler: { [internalCallbacks] state in
            let internalAction = internalCallbacks.headersCompleteHandler(state)
            let userAction = headersCompleteHandler?(state)
            switch (internalAction, userAction) {
            case (_, .none):
                return internalAction
            case (.proceed, .proceed):
                return .proceed
            case (.error, _), (_, .error):
                return .error
            case (.pause, _), (_, .pause):
                return .pause
            case (.assumeNoBodyAndContinue, _), (_, .assumeNoBodyAndContinue):
                return .assumeNoBodyAndContinue
            case (.assumeNoBodyAndPauseUpgrade, _), (_, .assumeNoBodyAndPauseUpgrade):
                return .assumeNoBodyAndPauseUpgrade
            }
        }

    }
}

private extension LLHTTP {
    func setInternalCallbacks(signalHandler: @escaping SignalHandler = { _, _ in .proceed },
                                       payloadHandler: @escaping PayloadHandler = { _, _ in .proceed },
                                       headersCompleteHandler: @escaping HeadersCompleteHandler = { _ in .proceed }) {
        guard let preconcurrency = preconcurrency as? LLHTTPPreconcurrencyProxy else {
            assertionFailure("Unable to cast preconcurrency to LLHTTPPreconcurrencyProxy")
            return
        }
        preconcurrency.setInternalCallbacks(signalHandler: signalHandler, payloadHandler: payloadHandler, headersCompleteHandler: headersCompleteHandler)
    }
}

import Foundation
@testable import llhttp

/// Minimal HTTP messages for testing wrapper functionality
enum TestHTTP {
    /// Minimal valid HTTP request
    static let minimalRequest = "GET / HTTP/1.1\r\n\r\n".data(using: .ascii)!
    
    /// Minimal HTTP request with headers
    static let requestWithHeaders = """
        GET /path HTTP/1.1\r
        Host: example.com\r
        Content-Length: 5\r
        \r
        Hello
        """.data(using: .ascii)!
    
    /// Minimal HTTP response
    static let minimalResponse = "HTTP/1.1 200 OK\r\n\r\n".data(using: .ascii)!
    
    /// Minimal HTTP response with headers
    static let responseWithHeaders = """
        HTTP/1.1 404 Not Found\r
        Content-Type: text/plain\r
        Content-Length: 9\r
        \r
        Not Found
        """.data(using: .ascii)!
    
    /// Invalid HTTP data
    static let invalidData = "INVALID HTTP\r\n".data(using: .ascii)!
    
    /// HTTP/1.0 request (for testing version detection)
    static let http10Request = "GET / HTTP/1.0\r\n\r\n".data(using: .ascii)!
    
    /// Request with Upgrade header (for testing upgrade detection)
    static let upgradeRequest = """
        GET /ws HTTP/1.1\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        \r

        """.data(using: .ascii)!
    
    /// Chunked response (minimal, just to test chunk callbacks)
    static let singleChunkResponse = """
        HTTP/1.1 200 OK\r
        Transfer-Encoding: chunked\r
        \r
        5\r
        Hello\r
        0\r
        \r\n
        """.data(using: .ascii)!

    static let multipleChunksResponse = """
        HTTP/1.1 200 OK\r
        Transfer-Encoding: chunked\r
        \r
        5\r
        Hello\r
        5\r
        World\r
        0\r
        \r\n
        """.data(using: .ascii)!
}

/// Records callback invocations for testing
final class CallbackRecorder: @unchecked Sendable {
    private var _signals: [LLHTTP.Signal] = []
    private var _payloads: [(LLHTTP.PayloadType, Data)] = []
    private var _headersComplete: [(method: String?, statusCode: Int32?, upgrade: Bool, keepAlive: Bool)] = []
    private var _states: [LLHTTP.State] = []
    
    var signals: [LLHTTP.Signal] { _signals }
    var payloads: [(LLHTTP.PayloadType, Data)] { _payloads }
    var headersComplete: [(method: String?, statusCode: Int32?, upgrade: Bool, keepAlive: Bool)] { _headersComplete }
    var states: [LLHTTP.State] { _states }
    
    func recordSignal(_ signal: LLHTTP.Signal, state: LLHTTP.State) -> LLHTTP.SignalAction {
        _signals.append(signal)
        _states.append(state)
        return .proceed
    }
    
    func recordPayload(_ payload: LLHTTP.Payload, state: LLHTTP.State) -> LLHTTP.PayloadAction {
        _payloads.append((payload.type, payload.data))
        _states.append(state)
        return .proceed
    }
    
    func recordHeadersComplete(_ state: LLHTTP.State) -> LLHTTP.HeadersCompleteAction {
        _headersComplete.append((
            method: state.method,
            statusCode: state.statusCode,
            upgrade: state.upgrade,
            keepAlive: state.shouldKeepAlive
        ))
        _states.append(state)
        return .proceed
    }
    
    func reset() {
        _signals.removeAll()
        _payloads.removeAll()
        _headersComplete.removeAll()
        _states.removeAll()
    }
}

func createMockState(
    type: LLHTTP.Mode = .both,
    majorVersion: UInt8 = 0,
    minorVersion: UInt8 = 0,
    method: String? = nil,
    statusCode: Int32? = nil,
    statusName: String? = nil,
    upgrade: Bool = false,
    contentLength: UInt64 = 0,
    shouldKeepAlive: Bool = false,
    messageNeedsEOF: Bool = false
) -> LLHTTP.State {
    return LLHTTP.State(
        type: type,
        majorVersion: majorVersion,
        minorVersion: minorVersion,
        method: method,
        statusCode: statusCode,
        statusName: statusName,
        upgrade: upgrade,
        contentLength: contentLength,
        shouldKeepAlive: shouldKeepAlive,
        messageNeedsEOF: messageNeedsEOF
    )
}

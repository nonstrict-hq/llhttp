import Testing
import Foundation
@testable import llhttp

@Suite
struct HTTPMessagesParserTests {

    @Suite
    struct BasicParserPropertiesTests {
        
        @Test
        func testParserHasLLHTTPInstance() async {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser(mode: HTTPMessage.Request.self)
            let llhttp = await parser.llhttp
            
            // LLHTTP instance is available and properly initialized
            _ = llhttp // Verify we can access the llhttp instance
        }
        
        @Test
        func testDefaultMessageHandler() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = HTTPMessagesParser<HTTPMessage.Request>()
            let handler = parser.messageHandler
            
            // Default handler should always return proceed
            let mockRequest = try #require(HTTPMessage.Request(builder: MockHTTPMessageBuilder()))
            let action = try handler(mockRequest)
            #expect(action == .proceed)
        }
    }
    
    @Suite
    struct ParsingTests {
        
        @Test
        func testParseSimpleRequest() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Request>()

            // Parse a simple request
            let messages = try await parser.parse(TestHTTP.minimalRequest)

            // Verify message was parsed
            let firstMessage = try #require(messages.first)
            #expect(firstMessage.method == "GET")
            #expect(firstMessage.url == "/")
            #expect(firstMessage.version == "1.1")
            #expect(firstMessage.protocol == "HTTP")
        }
        
        @Test
        func testParseSimpleResponse() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Response>()

            _ = try await parser.parse(TestHTTP.minimalResponse)
            let messages = try await parser.finish()

            let firstMessage = try #require(messages.first)
            #expect(firstMessage.status == "OK")
            #expect(firstMessage.version == "1.1")
            #expect(firstMessage.protocol == "HTTP")
        }
        
        @Test
        func testParseRequestWithHeadersAndBody() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Request>()

            let messages = try await parser.parse(TestHTTP.requestWithHeaders)

            let firstMessage = try #require(messages.first)
            #expect(firstMessage.method == "GET")
            #expect(firstMessage.url == "/path")
            #expect(firstMessage.headers["Host"] == ["example.com"])
            #expect(firstMessage.headers["Content-Length"] == ["5"])

            #expect(firstMessage.body == .single("Hello".data(using: .ascii)!))
        }
        
        @Test
        func testParsePipelinedRequests() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Request>()

            // Two requests in one buffer
            let pipelinedData = TestHTTP.minimalRequest + TestHTTP.minimalRequest
            let messages = try await parser.parse(pipelinedData)

            #expect(messages.count == 2)

            // Both should be identical minimal requests
            for message in messages {
                #expect(message.method == "GET")
                #expect(message.url == "/")
            }
        }
        
        @Test
        func testStreamingMessages() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Request>()

            // Parse multiple requests sequentially
            let messages1 = try await parser.parse(TestHTTP.minimalRequest)
            let messages2 = try await parser.parse(TestHTTP.requestWithHeaders)

            #expect(messages1.count == 1)
            #expect(messages2.count == 1)
            #expect(messages1.first?.method == "GET")
            #expect(messages2.first?.method == "GET")
        }
    }
    
    @Suite
    struct MessageHandlerTests {
        
        @Test
        func testMessageHandlerPause() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = HTTPMessagesParser<HTTPMessage.Request>()
            
            let handledMessages = UncheckedSendableBox(0)
            
            // Set message handler that pauses after first message
            parser.messageHandler = { message in
                handledMessages.value += 1
                return .pause
            }
            
            // Parsing should pause after first message
            await #expect(throws: LLHTTPError.self) {
                try await parser.parse(TestHTTP.minimalRequest)
            }
            
            #expect(handledMessages.value == 1)
        }
        
        @Test
        func testMessageHandlerProceed() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = HTTPMessagesParser<HTTPMessage.Request>()
            
            let handledMessages = UncheckedSendableBox(0)
            
            // Set message handler that proceeds
            parser.messageHandler = { message in
                handledMessages.value += 1
                return .proceed
            }
            
            _ = try await parser.parse(TestHTTP.minimalRequest)

            #expect(handledMessages.value == 1)
        }
        
        @Test
        func testMessageHandlerReceivesCorrectData() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = HTTPMessagesParser<HTTPMessage.Request>()
            
            let capturedMethod = UncheckedSendableBox<String?>(nil)
            let capturedURL = UncheckedSendableBox<String?>(nil)
            
            // Set message handler to capture data
            parser.messageHandler = { message in
                capturedMethod.value = message.method
                capturedURL.value = message.url
                return .proceed
            }
            
            _ = try await parser.parse(TestHTTP.requestWithHeaders)

            #expect(capturedMethod.value == "GET")
            #expect(capturedURL.value == "/path")
        }
        
        @Test
        func testMessageHandlerThrowsError() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = HTTPMessagesParser<HTTPMessage.Request>()
            
            struct CustomError: Error {}
            
            // Set message handler that throws
            parser.messageHandler = { message in
                throw CustomError()
            }
            
            await #expect(throws: LLHTTPError(code: 18, name: "HPE_CB_MESSAGE_COMPLETE", reason: "`on_message_complete` callback error")) {
                try await parser.parse(TestHTTP.minimalRequest)
            }
        }
    }
    
    @Suite
    struct ErrorHandlingTests {
        
        @Test
        func testInvalidHTTPDataThrowsError() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = HTTPMessagesParser<HTTPMessage.Request>()
            
            await #expect(throws: LLHTTPError.self) {
                try await parser.parse(TestHTTP.invalidData)
            }
        }
        
        @Test
        func testParserRecoversAfterReset() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Request>()

            // First parse invalid data
            await #expect(throws: LLHTTPError.self) {
                try await parser.parse(TestHTTP.invalidData)
            }

            await parser.llhttp.reset()

            // Then parse valid data
            let messages = try await parser.parse(TestHTTP.minimalRequest)

            // Parser should recover and parse valid data
            #expect(messages.count >= 1)
        }
    }
    
    @Suite
    struct PartialMessageHandlingTests {
        
        @Test
        func testParseMessageInChunks() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Request>()

            // Split request into parts
            let fullRequest = "GET /test HTTP/1.1\r\nHost: example.com\r\nContent-Length: 0\r\n\r\n".data(using: .ascii)!
            let part1 = fullRequest[0..<20]
            let part2 = fullRequest[20..<40]
            let part3 = fullRequest[40..<fullRequest.count]

            // Parse in parts - first two parts won't complete a message
            let messages1 = try await parser.parse(part1)
            let messages2 = try await parser.parse(part2)
            let messages3 = try await parser.parse(part3)

            #expect(messages1.isEmpty)
            #expect(messages2.isEmpty)
            #expect(messages3.count == 1)

            let firstMessage = try #require(messages3.first)
            #expect(firstMessage.method == "GET")
            #expect(firstMessage.url == "/test")
            #expect(firstMessage.headers["Host"] == ["example.com"])
        }
        
        @Test
        func testIncompleteMessage() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Request>()

            // Send only partial request
            let partialRequest = "GET /test HTTP/1.1\r\nHost: examp".data(using: .ascii)!
            let messages = try await parser.parse(partialRequest)

            // No complete message should be available yet
            #expect(messages.isEmpty)
        }
    }
    
    @Suite
    struct ChunkedTransferEncodingTests {

        @Test
        func testParseChunkedResponse() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Response>()

            let messages = try await parser.parse(TestHTTP.multipleChunksResponse)

            let firstMessage = try #require(messages.first)
            #expect(firstMessage.status == "OK")

            #expect(firstMessage.body == .chunked([.init(data: "Hello".data(using: .ascii)!, extensions: [:]), .init(data: "World".data(using: .ascii)!, extensions: [:])]))
        }
        
        @Test
        func testChunkedWithExtensions() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Response>()

            let chunkedWithExtensions = """
                HTTP/1.1 200 OK\r
                Transfer-Encoding: chunked\r
                \r
                5;charset=utf-8\r
                Hello\r
                0\r
                \r\n
                """.data(using: .ascii)!

            let messages = try await parser.parse(chunkedWithExtensions)

            let firstMessage = try #require(messages.first)

            #expect(firstMessage.body == .chunked([.init(data: "Hello".data(using: .ascii)!, extensions: ["charset": ["utf-8"]])]))
        }
    }
    
    @Suite
    struct ConcurrentOperationsTests {

        @Test
        func testConcurrentParseCalls() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = HTTPMessagesParser<HTTPMessage.Request>()

            // Attempt concurrent parsing (actor should serialize)
            async let messages1 = parser.parse(TestHTTP.minimalRequest)
            async let messages2 = parser.parse(TestHTTP.requestWithHeaders)

            let result1 = try await messages1
            let result2 = try await messages2

            // Actor should handle concurrent calls safely
            #expect(result1.count + result2.count == 2)
        }
    }
}

// Tests for the Preconcurrency class
@Suite
struct HTTPMessagesParserPreconcurrencyTests {
    
    @Test
    func testPreconcurrencyHasLLHTTP() {
        let parser = HTTPMessagesParser<HTTPMessage.Request>.Preconcurrency()
        
        // Preconcurrency has llhttp proxy
        _ = parser.llhttp // Verify proxy is accessible
    }
    
    @Test
    func testPreconcurrencyDefaultHandler() throws {
        let parser = HTTPMessagesParser<HTTPMessage.Request>.Preconcurrency()
        
        // Default handler should return proceed
        let mockRequest = try #require(HTTPMessage.Request(builder: MockHTTPMessageBuilder()))
        let action = try parser.messageHandler(mockRequest)
        #expect(action == .proceed)
    }
    
    @Test
    func testPreconcurrencyParsing() throws {
        let parser = HTTPMessagesParser<HTTPMessage.Request>.Preconcurrency()

        // Synchronous parsing works correctly
        let messages = try parser.parse(TestHTTP.requestWithHeaders)

        #expect(messages.count == 1)
        #expect(messages[0].method == "GET")
        #expect(messages[0].url == "/path")
    }
    
    @Test
    func testPreconcurrencyErrorHandling() throws {
        let parser = HTTPMessagesParser<HTTPMessage.Request>.Preconcurrency()
        
        // Errors are thrown synchronously
        #expect(throws: Error.self) {
            try parser.parse(TestHTTP.invalidData)
        }
    }

    @Test
    func testProxyCallbackIsForwarded() throws {
        let proxy = LLHTTPPreconcurrencyProxy(mode: .both)
        
        var signalReceived = false
        var payloadReceived = false
        var headersCompleteReceived = false

        // Test public setCallbacks override
        proxy.setCallbacks(
            signalHandler: { signal, state in
                signalReceived = true
                return .proceed
            },
            payloadHandler: { payload, state in
                payloadReceived = true
                return .proceed
            },
            headersCompleteHandler: { state in
                headersCompleteReceived = true
                return .proceed
            }
        )
        
        #expect(signalReceived == false) // Not triggered yet
        #expect(payloadReceived == false) // Not triggered yet
        #expect(headersCompleteReceived == false) // Not triggered yet

        try proxy.parse(TestHTTP.minimalRequest)

        #expect(signalReceived)
        #expect(payloadReceived)
        #expect(headersCompleteReceived)
    }
    
    @Test
    func testProxyInternalCallback() throws {
        let proxy = LLHTTPPreconcurrencyProxy(mode: .request)

        var signalReceived = false
        var payloadReceived = false
        var headersCompleteReceived = false

        proxy.setInternalCallbacks(
            signalHandler: { signal, state in
                signalReceived = true
                return .proceed
            },
            payloadHandler: { payload, state in
                payloadReceived = true
                return .proceed
            },
            headersCompleteHandler: { state in
                headersCompleteReceived = true
                return .proceed
            }
        )

        #expect(signalReceived == false) // Not triggered yet
        #expect(payloadReceived == false) // Not triggered yet
        #expect(headersCompleteReceived == false) // Not triggered yet

        try proxy.parse(TestHTTP.minimalRequest)

        #expect(signalReceived)
        #expect(payloadReceived)
        #expect(headersCompleteReceived)
    }

    @Test
    func testMessageHandlerCalledWhenMessageComplete() throws {
        let parser = HTTPMessagesParser<HTTPMessage.Request>.Preconcurrency()

        var handlerCalled = false
        var capturedMessage: HTTPMessage.Request?

        parser.messageHandler = { message in
            handlerCalled = true
            capturedMessage = message
            return .proceed
        }

        // Parse complete message
        let messages = try parser.parse(TestHTTP.minimalRequest)

        // Verify handler was called
        #expect(handlerCalled)
        #expect(capturedMessage != nil)
        #expect(capturedMessage?.method == "GET")

        // Verify parse also returned the message
        #expect(messages.count == 1)
        #expect(messages[0].method == "GET")
    }

    @Test
    func testMessageHandlerNotCalledWhenMessageIncomplete() throws {
        let parser = HTTPMessagesParser<HTTPMessage.Request>.Preconcurrency()

        var handlerCalled = false

        parser.messageHandler = { message in
            handlerCalled = true
            return .proceed
        }

        // Parse incomplete message (just the start of a request)
        let partialRequest = "GET /test HTTP/1.1\r\nHost: exam".data(using: .ascii)!
        let messages = try parser.parse(partialRequest)

        // Verify handler was NOT called since message is incomplete
        #expect(handlerCalled == false)

        // Verify parse returned no messages
        #expect(messages.isEmpty)
    }
}

// Mock builder for testing
private struct MockHTTPMessageBuilder: AnyHTTPMessageBuilder {
    let type: LLHTTP.Mode = .request
    let headerValues: [LLHTTP.PayloadType: [Data]] = [
        .method: ["GET".data(using: .ascii)!],
        .url: ["/".data(using: .ascii)!],
        .version: ["1.1".data(using: .ascii)!],
        .protocol: ["HTTP".data(using: .ascii)!]
    ]
    let chunkValues: [[LLHTTP.PayloadType: [Data]]] = [[:]]
}

// Helper for Swift 6 strict concurrency - allows mutation across concurrency boundaries
private final class UncheckedSendableBox<T>: @unchecked Sendable {
    var value: T
    
    init(_ value: T) {
        self.value = value
    }
}

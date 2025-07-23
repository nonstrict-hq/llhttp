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

            let parser = await HTTPMessagesParser(mode: HTTPMessage.Request.self)
            let llhttp = await parser.llhttp
            
            // LLHTTP instance is available and properly initialized
            _ = llhttp // Verify we can access the llhttp instance
        }
        
        @Test
        func testDefaultMessageHandler() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
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
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            // Set up stream consumer to collect messages
            let messageCollector = MessageCollector<HTTPMessage.Request>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }
            
            // Parse a simple request
            try await parser.parse(TestHTTP.minimalRequest)
            
            // Wait for processing and verify message was parsed
            let messages = await messageCollector.getMessages()
            let firstMessage = try #require(messages.first)
            #expect(firstMessage.method == "GET")
            #expect(firstMessage.url == "/")
            #expect(firstMessage.version == "1.1")
            #expect(firstMessage.protocol == "HTTP")
        }
        
        @Test
        func testParseSimpleResponse() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Response>()
            
            let messageCollector = MessageCollector<HTTPMessage.Response>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }
            
            try await parser.parse(TestHTTP.minimalResponse)
            try await parser.llhttp.finish()

            let messages = await messageCollector.getMessages()
            let firstMessage = try #require(messages.first)
            #expect(firstMessage.status == "OK")
            #expect(firstMessage.version == "1.1")
            #expect(firstMessage.protocol == "HTTP")
        }
        
        @Test
        func testParseRequestWithHeadersAndBody() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            let messageCollector = MessageCollector<HTTPMessage.Request>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }
            
            try await parser.parse(TestHTTP.requestWithHeaders)
            
            let messages = await messageCollector.getMessages()
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
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            let messageCollector = MessageCollector<HTTPMessage.Request>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }
            
            // Two requests in one buffer
            let pipelinedData = TestHTTP.minimalRequest + TestHTTP.minimalRequest
            try await parser.parse(pipelinedData)
            
            let messages = await messageCollector.getMessages()
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
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            let messageCounter = MessageCounter()
            let streamTask = Task {
                for await message in await parser.completedMessages {
                    await messageCounter.increment()
                    #expect(message.method == "GET")
                }
            }
            
            // Parse multiple requests sequentially
            try await parser.parse(TestHTTP.minimalRequest)
            try await parser.parse(TestHTTP.requestWithHeaders)
            
            // Give stream time to process
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            streamTask.cancel()
            
            #expect(await messageCounter.getCount() == 2)
        }
    }
    
    @Suite
    struct MessageHandlerTests {
        
        @Test
        func testMessageHandlerPause() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
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
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            let handledMessages = UncheckedSendableBox(0)
            
            // Set message handler that proceeds
            parser.messageHandler = { message in
                handledMessages.value += 1
                return .proceed
            }
            
            try await parser.parse(TestHTTP.minimalRequest)
            
            #expect(handledMessages.value == 1)
        }
        
        @Test
        func testMessageHandlerReceivesCorrectData() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            let capturedMethod = UncheckedSendableBox<String?>(nil)
            let capturedURL = UncheckedSendableBox<String?>(nil)
            
            // Set message handler to capture data
            parser.messageHandler = { message in
                capturedMethod.value = message.method
                capturedURL.value = message.url
                return .proceed
            }
            
            try await parser.parse(TestHTTP.requestWithHeaders)
            
            #expect(capturedMethod.value == "GET")
            #expect(capturedURL.value == "/path")
        }
        
        @Test
        func testMessageHandlerThrowsError() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
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
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            await #expect(throws: LLHTTPError.self) {
                try await parser.parse(TestHTTP.invalidData)
            }
        }
        
        @Test
        func testParserRecoversAfterReset() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            // First parse invalid data
            await #expect(throws: LLHTTPError.self) {
                try await parser.parse(TestHTTP.invalidData)
            }

            await parser.llhttp.reset()

            // Then parse valid data
            let messageCollector = MessageCollector<HTTPMessage.Request>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }
            
            try await parser.parse(TestHTTP.minimalRequest)
            
            // Parser should recover and parse valid data
            let messages = await messageCollector.getMessages()
            #expect(messages.count >= 1)
        }
    }
    
    @Suite
    struct PartialMessageHandlingTests {
        
        @Test
        func testParseMessageInChunks() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            let messageCollector = MessageCollector<HTTPMessage.Request>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }
            
            // Split request into parts
            let fullRequest = "GET /test HTTP/1.1\r\nHost: example.com\r\nContent-Length: 0\r\n\r\n".data(using: .ascii)!
            let part1 = fullRequest[0..<20]
            let part2 = fullRequest[20..<40]
            let part3 = fullRequest[40..<fullRequest.count]
            
            // Parse in parts
            try await parser.parse(part1)
            try await parser.parse(part2)
            try await parser.parse(part3)
            
            let messages = await messageCollector.getMessages()
            let firstMessage = try #require(messages.first)
            #expect(firstMessage.method == "GET")
            #expect(firstMessage.url == "/test")
            #expect(firstMessage.headers["Host"] == ["example.com"])
        }
        
        @Test
        func testIncompleteMessage() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Request>()
            
            let messageCollector = MessageCollector<HTTPMessage.Request>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }
            
            // Send only partial request
            let partialRequest = "GET /test HTTP/1.1\r\nHost: examp".data(using: .ascii)!
            try await parser.parse(partialRequest)
            
            // No complete message should be available yet
            let messages = await messageCollector.getMessages()
            #expect(messages.isEmpty)
        }
    }
    
    @Suite
    struct ChunkedTransferEncodingTests {

        @Test
        func testParseChunkedResponse() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Response>()
            
            let messageCollector = MessageCollector<HTTPMessage.Response>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }
            
            try await parser.parse(TestHTTP.multipleChunksResponse)

            let messages = await messageCollector.getMessages()
            let firstMessage = try #require(messages.first)
            #expect(firstMessage.status == "OK")
            
            #expect(firstMessage.body == .chunked([.init(data: "Hello".data(using: .ascii)!, extensions: [:]), .init(data: "World".data(using: .ascii)!, extensions: [:])]))
        }
        
        @Test
        func testChunkedWithExtensions() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }
            
            let parser = await HTTPMessagesParser<HTTPMessage.Response>()
            
            let messageCollector = MessageCollector<HTTPMessage.Response>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }
            
            let chunkedWithExtensions = """
                HTTP/1.1 200 OK\r
                Transfer-Encoding: chunked\r
                \r
                5;charset=utf-8\r
                Hello\r
                0\r
                \r\n
                """.data(using: .ascii)!
            
            try await parser.parse(chunkedWithExtensions)
            
            let messages = await messageCollector.getMessages()
            let firstMessage = try #require(messages.first)
            
            #expect(firstMessage.body == .chunked([.init(data: "Hello".data(using: .ascii)!, extensions: ["charset": ["utf-8"]])]))
        }
    }
    
    @Suite
    struct ConcurrentOperationsTests {

        @Test
        func testConcurrentParseCalls() async throws {
            guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return }

            let parser = await HTTPMessagesParser<HTTPMessage.Request>()

            let messageCollector = MessageCollector<HTTPMessage.Request>()
            Task {
                for await message in await parser.completedMessages {
                    await messageCollector.addMessage(message)
                }
            }

            // Attempt concurrent parsing (actor should serialize)
            async let parse1: Void = parser.parse(TestHTTP.minimalRequest)
            async let parse2: Void = parser.parse(TestHTTP.requestWithHeaders)

            try await parse1
            try await parse2

            // Actor should handle concurrent calls safely
            let messages = await messageCollector.getMessages()
            #expect(messages.count == 2)
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
        
        var handledMessages = 0
        parser.messageHandler = { message in
            handledMessages += 1
            #expect(message.method == "GET")
            return .proceed
        }
        
        // Synchronous parsing works correctly
        try parser.parse(TestHTTP.requestWithHeaders)

        #expect(handledMessages == 1)
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
}

// Helper actor for collecting messages from streams
private actor MessageCollector<MessageType> {
    private var messages: [MessageType] = []
    
    func addMessage(_ message: MessageType) {
        messages.append(message)
    }
    
    func getMessages(after seconds: TimeInterval = 0.1) async -> [MessageType] {
        try? await Task.sleep(for: .seconds(seconds))
        return messages
    }
}

// Helper actor for counting messages
private actor MessageCounter {
    private var count = 0
    
    func increment() {
        count += 1
    }
    
    func getCount() -> Int {
        return count
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

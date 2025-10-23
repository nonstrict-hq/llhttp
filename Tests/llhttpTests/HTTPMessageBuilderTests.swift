import Testing
import Foundation
@testable import llhttp

@Suite
struct HTTPMessageBuilderTests {
    
    @Suite
    struct PayloadHandlingTests {
        
        @Test
        func testInitialState() {
            let builder = HTTPMessageBuilder()
            
            // Verify initial state
            #expect(builder.type == .both)
            #expect(builder.headerValues.isEmpty)
            #expect(builder.chunkValues == [[:]]) // Single empty chunk
        }
        
        @Test
        func testBuilderPropertiesReadOnly() {
            let builder = HTTPMessageBuilder()
            
            // These properties should be private(set) or let
            #expect(builder.type == .both)
            #expect(builder.headerValues.isEmpty)
            #expect(builder.chunkValues.count == 1)
        }
        
        @Test
        func testAppendMethodPayload() {
            var builder = HTTPMessageBuilder()
            
            let state = createMockState(type: .request)
            let methodPayload = LLHTTP.Payload(type: .method, data: "GET".data(using: .ascii)!)
            builder.append(methodPayload, state: state)
            #expect(builder.headerValues[.method] == ["GET".data(using: .ascii)!])
            #expect(builder.type == .request)
        }
        
        @Test
        func testAppendMultiplePayloadFragments() {
            var builder = HTTPMessageBuilder()
            
            let state = createMockState()
            let urlPayload1 = LLHTTP.Payload(type: .url, data: "/some".data(using: .ascii)!)
            let urlPayload2 = LLHTTP.Payload(type: .url, data: "/path".data(using: .ascii)!)
            
            builder.append(urlPayload1, state: state)
            builder.append(urlPayload2, state: state)
            
            let combinedURL = builder.headerValues[.url]?.reduce(Data(), +)
            #expect(combinedURL == "/some/path".data(using: .ascii)!)
        }
        
        @Test
        func testAppendHeaderFieldsAndValues() throws {
            var builder = HTTPMessageBuilder()
            let state = createMockState()
            
            // Header 1
            builder.append(LLHTTP.Payload(type: .headerField, data: "Host".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.headerFieldComplete, state: state)
            builder.append(LLHTTP.Payload(type: .headerValue, data: "example.com".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.headerValueComplete, state: state)

            // Header 2
            builder.append(LLHTTP.Payload(type: .headerField, data: "Cookie".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.headerFieldComplete, state: state)
            builder.append(LLHTTP.Payload(type: .headerValue, data: "a=1".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.headerValueComplete, state: state)

            try #require(builder.headerValues[.headerField]?.count == 3)
            try #require(builder.headerValues[.headerValue]?.count == 3)
            #expect(builder.headerValues[.headerField]?[0] == "Host".data(using: .ascii)!)
            #expect(builder.headerValues[.headerValue]?[0] == "example.com".data(using: .ascii)!)
            #expect(builder.headerValues[.headerField]?[1] == "Cookie".data(using: .ascii)!)
            #expect(builder.headerValues[.headerValue]?[1] == "a=1".data(using: .ascii)!)
            #expect(builder.headerValues[.headerField, default: []][2].isEmpty)
            #expect(builder.headerValues[.headerValue, default: []][2].isEmpty)
        }
        
        @Test
        func testAppendBodyPayload() {
            var builder = HTTPMessageBuilder()
            let state = createMockState()
            
            builder.append(LLHTTP.Payload(type: .body, data: "part1".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.chunkComplete, state: state)
            builder.append(LLHTTP.Payload(type: .body, data: "part2".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.chunkComplete, state: state)

            let combinedBody = builder.chunkValues.compactMap { $0[.body] }.flatMap { $0 }.reduce(Data(), +)
            #expect(combinedBody == "part1part2".data(using: .ascii)!)
        }
        
        @Test
        func testChunkedTransferEncoding() {
            var builder = HTTPMessageBuilder()
            let state = createMockState()

            // Chunk 1
            let _: HTTPMessage? = builder.append(.chunkHeader, state: state)
            builder.append(LLHTTP.Payload(type: .chunkExtensionName, data: "ext1".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.chunkExtensionNameComplete, state: state)
            builder.append(LLHTTP.Payload(type: .chunkExtensionValue, data: "val1".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.chunkExtensionValueComplete, state: state)
            builder.append(LLHTTP.Payload(type: .body, data: "chunk body 1".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.chunkComplete, state: state)

            // Chunk 2
            let _: HTTPMessage? = builder.append(.chunkHeader, state: state)
            builder.append(LLHTTP.Payload(type: .body, data: "chunk body 2".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.chunkComplete, state: state)

            #expect(builder.chunkValues.count == 3) // 2 chunks + ready to be used empty one

            // Check chunk 1 (at index 0)
            #expect(builder.chunkValues[0][.chunkExtensionName]?.first == "ext1".data(using: .ascii)!)
            #expect(builder.chunkValues[0][.chunkExtensionValue]?.first == "val1".data(using: .ascii)!)
            #expect(builder.chunkValues[0][.body]?.first == "chunk body 1".data(using: .ascii)!)

            // Check chunk 2 (at index 1)
            #expect(builder.chunkValues[1][.body]?.first == "chunk body 2".data(using: .ascii)!)
            #expect(builder.chunkValues[1][.chunkExtensionName] == nil)
            #expect(builder.chunkValues[1][.chunkExtensionValue] == nil)
        }
    }
    
    @Suite
    struct SignalHandlingTests {
        
        @Test
        func testMessageBeginSignal() {
            var builder = HTTPMessageBuilder()
            let state = createMockState(type: .both)

            let message: HTTPMessage? = builder.append(.messageBegin, state: state)
            
            #expect(message == nil)
            #expect(builder.headerValues.isEmpty)
            #expect(builder.chunkValues == [[:]])
            #expect(builder.type == .both)
        }
        
        @Test
        func testCompleteSignals() {
            var builder = HTTPMessageBuilder()
            let state = createMockState()

            builder.append(LLHTTP.Payload(type: .url, data: "/".data(using: .ascii)!), state: state)
            let message1: HTTPMessage? = builder.append(.urlComplete, state: state)
            #expect(message1 == nil)
            #expect(builder.headerValues[.url] != nil)

            builder.append(LLHTTP.Payload(type: .headerField, data: "Host".data(using: .ascii)!), state: state)
            let message2: HTTPMessage? = builder.append(.headerFieldComplete, state: state)
            #expect(message2 == nil)

            builder.append(LLHTTP.Payload(type: .headerValue, data: "example.com".data(using: .ascii)!), state: state)
            let message3: HTTPMessage? = builder.append(.headerValueComplete, state: state)
            #expect(message3 == nil)

            builder.append(LLHTTP.Payload(type: .body, data: "test".data(using: .ascii)!), state: state)
        }
        
        @Test
        func testMessageCompleteReturnsMessage() {
            var builder = HTTPMessageBuilder()
            let state = createMockState(type: .request)

            builder.append(LLHTTP.Payload(type: .protocol, data: "HTTP".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .version, data: "1.1".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .method, data: "POST".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .url, data: "/test".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .headerField, data: "Content-Length".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .headerValue, data: "4".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .body, data: "test".data(using: .ascii)!), state: state)
            let message: HTTPMessage? = builder.append(.messageComplete, state: state)
            let _: HTTPMessage? = builder.append(.reset, state: state)

            #expect(message != nil)
            if case .request(let request) = message {
                #expect(request.method == "POST")
                #expect(request.url == "/test")
                #expect(request.headers["Content-Length"] == ["4"])
                #expect(request.body == .single("test".data(using: .ascii)!))
            } else {
                #expect(Bool(false), "Expected request, got \(String(describing: message))")
            }
            
            // After message completion, builder should be reset
            #expect(builder.headerValues.isEmpty)
            #expect(builder.chunkValues == [[:]])
        }
        
        @Test
        func testResetSignal() {
            var builder = HTTPMessageBuilder()
            let state = createMockState(type: .request)

            builder.append(LLHTTP.Payload(type: .method, data: "GET".data(using: .ascii)!), state: state)
            #expect(builder.type == .request)

            let _: HTTPMessage? = builder.append(.reset, state: state)
            
            #expect(builder.type == .both)
            #expect(builder.headerValues.isEmpty)
            #expect(builder.chunkValues == [[:]])
        }
        
        @Test
        func testChunkSignals() throws {
            var builder = HTTPMessageBuilder()
            let state = createMockState()

            // Initial state
            #expect(builder.chunkValues.count == 1)
            #expect(builder.chunkValues[0].isEmpty)

            // First chunk
            let _: HTTPMessage? = builder.append(.chunkHeader, state: state)
            try #require(builder.chunkValues.count == 1)
            #expect(builder.chunkValues[0].isEmpty)
            builder.append(LLHTTP.Payload(type: .body, data: "chunk1".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.chunkComplete, state: state)
            #expect(builder.chunkValues.count == 2)
            #expect(builder.chunkValues[0][.body]?.first == "chunk1".data(using: .ascii)!)

            // Second chunk
            let _: HTTPMessage? = builder.append(.chunkHeader, state: state)
            #expect(builder.chunkValues.count == 2)
            builder.append(LLHTTP.Payload(type: .body, data: "chunk2".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.chunkComplete, state: state)
            #expect(builder.chunkValues.count == 3)
            #expect(builder.chunkValues[1][.body]?.first == "chunk2".data(using: .ascii)!)
        }
    }
    
    @Suite
    struct EdgeCaseTests {
        
        @Test
        func testPayloadOrderIndependence() {
            var builder1 = HTTPMessageBuilder()
            var builder2 = HTTPMessageBuilder()
            let state = createMockState(type: .request)

            let `protocol` = LLHTTP.Payload(type: .protocol, data: "HTTP".data(using: .ascii)!)
            let version = LLHTTP.Payload(type: .version, data: "1.1".data(using: .ascii)!)
            let method = LLHTTP.Payload(type: .method, data: "GET".data(using: .ascii)!)
            let url = LLHTTP.Payload(type: .url, data: "/".data(using: .ascii)!)

            // Order 1
            builder1.append(`protocol`, state: state)
            builder1.append(version, state: state)
            builder1.append(method, state: state)
            builder1.append(url, state: state)

            // Order 2
            builder2.append(`protocol`, state: state)
            builder2.append(version, state: state)
            builder2.append(url, state: state)
            builder2.append(method, state: state)

            let message1: HTTPMessage? = builder1.append(.messageComplete, state: state)
            let message2: HTTPMessage? = builder2.append(.messageComplete, state: state)

            #expect(message1 != nil)
            #expect(message2 != nil)
            
            if case .request(let req1) = message1, case .request(let req2) = message2 {
                #expect(req1.method == req2.method)
                #expect(req1.url == req2.url)
            } else {
                #expect(Bool(false), "Messages should be equal and of type request")
            }
        }
        
        @Test
        func testMultipleHeadersWithSameName() {
            var builder = HTTPMessageBuilder()
            let state = createMockState(type: .request)

            builder.append(LLHTTP.Payload(type: .protocol, data: "HTTP".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .version, data: "1.1".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .method, data: "GET".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .url, data: "/".data(using: .ascii)!), state: state)

            builder.append(LLHTTP.Payload(type: .headerField, data: "Set-Cookie".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.headerFieldComplete, state: state)
            builder.append(LLHTTP.Payload(type: .headerValue, data: "a=1".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.headerValueComplete, state: state)

            builder.append(LLHTTP.Payload(type: .headerField, data: "Set-Cookie".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.headerFieldComplete, state: state)
            builder.append(LLHTTP.Payload(type: .headerValue, data: "b=2".data(using: .ascii)!), state: state)
            let _: HTTPMessage? = builder.append(.headerValueComplete, state: state)

            let message: HTTPMessage? = builder.append(.messageComplete, state: state)

            #expect(message != nil)
            if case .request(let request) = message {
                #expect(request.headers["Set-Cookie"] == ["a=1", "b=2"])
            } else {
                #expect(Bool(false), "Expected request, got \(String(describing: message))")
            }
        }
        
        @Test
        func testVeryLargePayloadHandling() {
            var builder = HTTPMessageBuilder()
            let state = createMockState(type: .request)

            builder.append(LLHTTP.Payload(type: .protocol, data: "HTTP".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .version, data: "1.1".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .method, data: "GET".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .url, data: "/".data(using: .ascii)!), state: state)

            let largeData = Data(repeating: 0, count: 1_024 * 1_024) // 1MB
            builder.append(LLHTTP.Payload(type: .body, data: largeData), state: state)
            
            let message: HTTPMessage? = builder.append(.messageComplete, state: state)
            
            #expect(message != nil)
            if case .request(let request) = message {
                #expect(request.body == .single(largeData))
            } else {
                #expect(Bool(false), "Expected request, got \(String(describing: message))")
            }
        }
        
        @Test
        func testChunkExtensions() {
            var builder = HTTPMessageBuilder()
            let state = createMockState()

            let _: HTTPMessage? = builder.append(.chunkHeader, state: state)
            builder.append(LLHTTP.Payload(type: .chunkExtensionName, data: "ext1".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .chunkExtensionValue, data: "val1".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .chunkExtensionName, data: "ext2".data(using: .ascii)!), state: state)
            builder.append(LLHTTP.Payload(type: .chunkExtensionValue, data: "".data(using: .ascii)!), state: state) // extension with no value
            let _: HTTPMessage? = builder.append(.chunkComplete, state: state)

            #expect(builder.chunkValues.count == 2)
            let chunk = builder.chunkValues[0]
            
            #expect(chunk[.chunkExtensionName]?.reduce(Data(), +) == "ext1ext2".data(using: .ascii)!)
            #expect(chunk[.chunkExtensionValue]?.reduce(Data(), +) == "val1".data(using: .ascii)!)
        }
    }
}

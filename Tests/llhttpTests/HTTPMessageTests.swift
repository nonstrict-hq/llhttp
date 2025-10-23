import Testing
import Foundation
@testable import llhttp

@Suite
struct HTTPMessageTests {
    
    @Suite
    struct RequestTests {
        
        @Test
        func testRequestInitializationWithValidBuilder() throws {
            let builder = MockHTTPMessageBuilder(
                type: .request,
                headerValues: [
                    .method: ["GET".data(using: .ascii)!],
                    .url: ["/api/users".data(using: .ascii)!],
                    .version: ["1.1".data(using: .ascii)!],
                    .headerField: ["Host".data(using: .ascii)!, "Content-Type".data(using: .ascii)!],
                    .headerValue: ["example.com".data(using: .ascii)!, "application/json".data(using: .ascii)!],
                    .protocol: ["HTTP".data(using: .ascii)!]
                ],
                chunkValues: [
                    [.body: ["test body".data(using: .ascii)!]]
                ]
            )
            
            let request = try #require(HTTPRequest(builder: builder))
            #expect(request.method == "GET")
            #expect(request.url == "/api/users")
            #expect(request.version == "1.1")
            #expect(request.protocol == "HTTP")
            #expect(request.headers["Host"] == ["example.com"])
            #expect(request.headers["Content-Type"] == ["application/json"])
            
            #expect(request.body == .single("test body".data(using: .ascii)!))
        }
        
        @Test
        func testRequestWithEmptyBody() throws {
            let builder = MockHTTPMessageBuilder(
                type: .request,
                headerValues: [
                    .method: ["HEAD".data(using: .ascii)!],
                    .url: ["/".data(using: .ascii)!],
                    .version: ["1.1".data(using: .ascii)!],
                    .protocol: ["HTTP".data(using: .ascii)!]
                ]
            )
            
            let request = try #require(HTTPRequest(builder: builder))
            #expect(request.method == "HEAD")
            #expect(request.url == "/")
            
            #expect(request.body == .empty)
        }
        
        @Test
        func testRequestWithInvalidBuilderType() {
            let builder = MockHTTPMessageBuilder(type: .response)
            let request = HTTPRequest(builder: builder)
            #expect(request == nil)
        }
    }
    
    @Suite
    struct ResponseTests {
        
        @Test
        func testResponseInitializationWithValidBuilder() throws {
            let builder = MockHTTPMessageBuilder(
                type: .response,
                headerValues: [
                    .status: ["OK".data(using: .ascii)!],
                    .version: ["1.1".data(using: .ascii)!],
                    .protocol: ["HTTP".data(using: .ascii)!],
                    .headerField: ["Content-Type".data(using: .ascii)!, "Content-Length".data(using: .ascii)!],
                    .headerValue: ["text/html".data(using: .ascii)!, "1234".data(using: .ascii)!]
                ],
                chunkValues: [
                    [.body: ["<html>...</html>".data(using: .ascii)!]]
                ]
            )
            
            let response = try #require(HTTPResponse(builder: builder))
            #expect(response.status == "OK")
            #expect(response.version == "1.1")
            #expect(response.protocol == "HTTP")
            #expect(response.headers["Content-Type"] == ["text/html"])
            #expect(response.headers["Content-Length"] == ["1234"])
            
            #expect(response.body == .single("<html>...</html>".data(using: .ascii)!))
        }
        
        @Test
        func testResponseWithChunkedBody() throws {
            let builder = MockHTTPMessageBuilder(
                type: .response,
                headerValues: [
                    .status: ["OK".data(using: .ascii)!],
                    .protocol: ["HTTP".data(using: .ascii)!],
                    .version: ["1.1".data(using: .ascii)!],
                    .headerField: ["Transfer-Encoding".data(using: .ascii)!],
                    .headerValue: ["chunked".data(using: .ascii)!]
                ],
                chunkValues: [
                    [.body: ["Hello".data(using: .ascii)!]],
                    [.body: [" World".data(using: .ascii)!]]
                ]
            )
            
            let response = try #require(HTTPResponse(builder: builder))
            
            let expectedChunks = [
                HTTPMessage.Chunk(data: "Hello".data(using: .ascii)!, extensions: [:]),
                HTTPMessage.Chunk(data: " World".data(using: .ascii)!, extensions: [:])
            ]
            #expect(response.body == .chunked(expectedChunks))
        }
        
        @Test
        func testResponseWithInvalidBuilderType() {
            let builder = MockHTTPMessageBuilder(type: .request)
            let response = HTTPResponse(builder: builder)
            #expect(response == nil)
        }
    }
    
    @Suite
    struct BothTests {
        
        @Test
        func testBothInitializesAsRequest() throws {
            let builder = MockHTTPMessageBuilder(
                type: .request,
                headerValues: [
                    .method: ["POST".data(using: .ascii)!],
                    .url: ["/submit".data(using: .ascii)!],
                    .version: ["1.1".data(using: .ascii)!],
                    .protocol: ["HTTP".data(using: .ascii)!]
                ]
            )
            
            let both = try #require(HTTPMessage(builder: builder))
            
            if case .request(let request) = both {
                #expect(request.method == "POST")
                #expect(request.url == "/submit")
            } else {
                Issue.record("Expected request variant")
            }
        }
        
        @Test
        func testBothInitializesAsResponse() throws {
            let builder = MockHTTPMessageBuilder(
                type: .response,
                headerValues: [
                    .status: ["Not Found".data(using: .ascii)!],
                    .version: ["1.1".data(using: .ascii)!],
                    .protocol: ["HTTP".data(using: .ascii)!]
                ]
            )
            
            let both = try #require(HTTPMessage(builder: builder))
            
            if case .response(let response) = both {
                #expect(response.status == "Not Found")
            } else {
                Issue.record("Expected response variant")
            }
        }
        
        @Test
        func testBothComputedProperties() throws {
            // Test request variant
            let requestBuilder = MockHTTPMessageBuilder(
                type: .request,
                headerValues: [
                    .method: ["GET".data(using: .ascii)!],
                    .url: ["/test".data(using: .ascii)!],
                    .version: ["1.1".data(using: .ascii)!],
                    .protocol: ["HTTP".data(using: .ascii)!],
                    .headerField: ["Host".data(using: .ascii)!],
                    .headerValue: ["example.com".data(using: .ascii)!]
                ]
            )
            
            let requestBoth = try #require(HTTPMessage(builder: requestBuilder))
            #expect(requestBoth.method == "GET")
            #expect(requestBoth.url == "/test")
            #expect(requestBoth.status == nil)
            #expect(requestBoth.protocol == "HTTP")
            #expect(requestBoth.version == "1.1")
            #expect(requestBoth.headers["Host"] == ["example.com"])
            
            // Test response variant
            let responseBuilder = MockHTTPMessageBuilder(
                type: .response,
                headerValues: [
                    .status: ["OK".data(using: .ascii)!],
                    .version: ["2.0".data(using: .ascii)!],
                    .protocol: ["HTTP".data(using: .ascii)!]
                ]
            )
            
            let responseBoth = try #require(HTTPMessage(builder: responseBuilder))
            #expect(responseBoth.method == nil)
            #expect(responseBoth.url == nil)
            #expect(responseBoth.status == "OK")
            #expect(responseBoth.version == "2.0")
        }
        
        @Test
        func testBothWithInvalidBuilder() {
            let builder = MockHTTPMessageBuilder(
                type: .both,
                headerValues: [:]  // No method or status
            )
            
            let both = HTTPMessage(builder: builder)
            #expect(both == nil)
        }
    }
    
    @Suite
    struct BodyTests {
        
        @Test
        func testBodyInitializesAsEmpty() {
            let body = HTTPMessage.Body(chunkValues: [[:]]) 
            
            #expect(body == .empty)
            
            #expect(body.data == Data())
        }
        
        @Test
        func testBodyDataComputedProperty() {
            let testData = "Hello World".data(using: .ascii)!
            
            // Test single body
            let singleBody = HTTPMessage.Body.single(testData)
            #expect(singleBody.data == testData)
            
            // Test chunked body
            let chunk1 = HTTPMessage.Chunk(data: "Hello".data(using: .ascii)!, extensions: [:])
            let chunk2 = HTTPMessage.Chunk(data: " World".data(using: .ascii)!, extensions: [:])
            let chunkedBody = HTTPMessage.Body.chunked([chunk1, chunk2])
            #expect(chunkedBody.data == testData)
            
            // Test empty body
            let emptyBody = HTTPMessage.Body.empty
            #expect(emptyBody.data == Data())
        }
        
        @Test
        func testBodyWithChunkExtensions() {
            let chunk = HTTPMessage.Chunk(
                data: "test data".data(using: .ascii)!,
                extensions: ["name": ["value1", "value2"], "foo": ["bar"]]
            )
            
            #expect(chunk.data == "test data".data(using: .ascii)!)
            #expect(chunk.extensions["name"] == ["value1", "value2"])
            #expect(chunk.extensions["foo"] == ["bar"])
            #expect(chunk.extensions["missing"] == nil)
        }
        
        @Test
        func testBodyFromChunkValues() {
            // Test single data
            let singleBody = HTTPMessage.Body(chunkValues: [[.body: ["Hello".data(using: .ascii)!]]])
            #expect(singleBody == .single("Hello".data(using: .ascii)!))
        }

        @Test
        func testBodyFromMultipleChunkValues() {
            // Test chunked data
            let chunkedBody = HTTPMessage.Body(chunkValues: [
                [.body: ["Chunk1".data(using: .ascii)!]],
                [.body: ["Chunk2".data(using: .ascii)!]]
            ])
            let expectedChunks = [
                HTTPMessage.Chunk(data: "Chunk1".data(using: .ascii)!, extensions: [:]),
                HTTPMessage.Chunk(data: "Chunk2".data(using: .ascii)!, extensions: [:])
            ]
            #expect(chunkedBody == .chunked(expectedChunks))
            #expect(chunkedBody.data == "Chunk1Chunk2".data(using: .ascii)!)
        }
    }
}

// Mock builder for testing
private struct MockHTTPMessageBuilder: AnyHTTPMessageBuilder {
    let type: LLHTTP.Mode
    let headerValues: [LLHTTP.PayloadType: [Data]]
    let chunkValues: [[LLHTTP.PayloadType: [Data]]]
    
    init(type: LLHTTP.Mode,
         headerValues: [LLHTTP.PayloadType: [Data]] = [:],
         chunkValues: [[LLHTTP.PayloadType: [Data]]] = [[:]])
    {
        self.type = type
        self.headerValues = headerValues
        self.chunkValues = chunkValues
    }
}

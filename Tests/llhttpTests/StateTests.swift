import Testing
import Foundation
@testable import llhttp

@Suite("State Object")
struct StateTests {
    
    @Test("State properties for request")
    func testRequestStateProperties() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(headersCompleteHandler: { state in
            recorder.recordHeadersComplete(state)
        })
        
        try await parser.parse(TestHTTP.requestWithHeaders)
        
        #expect(!recorder.states.isEmpty)
        let state = recorder.states.last!
        
        // Verify request state properties
        #expect(state.type == .request)
        #expect(state.majorVersion == 1)
        #expect(state.minorVersion == 1)
        #expect(state.method == "GET")
        #expect(state.statusCode == nil)
        #expect(state.statusName == nil)
        #expect(state.contentLength == 5)
        #expect(state.shouldKeepAlive == true) // HTTP/1.1 defaults to keep-alive
    }
    
    @Test("State properties for response")
    func testResponseStateProperties() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .response)
        await parser.setCallbacks(headersCompleteHandler: { state in
            recorder.recordHeadersComplete(state)
        })
        
        try await parser.parse(TestHTTP.responseWithHeaders)
        
        #expect(!recorder.states.isEmpty)
        let state = recorder.states.last!
        
        // Verify response state properties
        #expect(state.type == .response)
        #expect(state.majorVersion == 1)
        #expect(state.minorVersion == 1)
        #expect(state.method == nil)
        #expect(state.statusCode == 404)
        #expect(state.statusName == "NOT_FOUND")
        #expect(state.contentLength == 9)
    }
    
    @Test("State version detection")
    func testStateVersionDetection() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(headersCompleteHandler: { state in
            recorder.recordHeadersComplete(state)
        })
        
        try await parser.parse(TestHTTP.http10Request)
        
        let state = recorder.states.last!
        #expect(state.majorVersion == 1)
        #expect(state.minorVersion == 0)
        #expect(state.shouldKeepAlive == false) // HTTP/1.0 defaults to close
    }
    
    @Test("State upgrade detection")
    func testStateUpgradeDetection() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(headersCompleteHandler: { state in
            recorder.recordHeadersComplete(state)
        })
        
        await #expect(throws: LLHTTPError(code: 22, name: "HPE_PAUSED_UPGRADE", reason: "Pause on CONNECT/Upgrade")) {
            try await parser.parse(TestHTTP.upgradeRequest)
        }
        
        #expect(!recorder.states.isEmpty)
        let state = recorder.states.last!
        #expect(state.upgrade == true)
    }
    
    @Test("State property access via parser")
    func testStatePropertyAccess() async throws {
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(headersCompleteHandler: { state in
            // Check state in headers complete callback
            #expect(state.method == "GET")
            #expect(state.contentLength == 5)
            return .proceed
        })
        
        // Parse the request
        try await parser.parse(TestHTTP.requestWithHeaders)
        
        // After reset
        await parser.reset()
        let resetState = await parser.state
        // After reset, content length should be 0
        #expect(resetState.contentLength == 0)
    }
    
    @Test("Response without Content-Length needs EOF")
    func testStateMessageNeedsEOFWithoutContentLength() async throws {
        let recorder = CallbackRecorder()
        
        let responseWithoutLength = """
            HTTP/1.1 200 OK\r
            Connection: close\r
            \r
            Some body content
            """.data(using: .ascii)!
        
        let parser = LLHTTP(mode: .response)
        await parser.setCallbacks(headersCompleteHandler: { state in
            recorder.recordHeadersComplete(state)
        })
        
        try await parser.parse(responseWithoutLength)
        
        #expect(!recorder.states.isEmpty)
        let state = recorder.states.last!
        #expect(state.messageNeedsEOF == true)
    }
    
    @Test("Response with Content-Length does not need EOF")
    func testStateMessageNeedsEOFWithContentLength() async throws {
        let recorder = CallbackRecorder()
        
        let responseWithLength = """
            HTTP/1.1 200 OK\r
            Content-Length: 5\r
            \r
            Hello
            """.data(using: .ascii)!
        
        let parser = LLHTTP(mode: .response)
        await parser.setCallbacks(headersCompleteHandler: { state in
            recorder.recordHeadersComplete(state)
        })
        
        try await parser.parse(responseWithLength)
        
        #expect(!recorder.states.isEmpty)
        let state = recorder.states.last!
        #expect(state.messageNeedsEOF == false)
    }
    
    @Test("Chunked response does not need EOF")
    func testStateMessageNeedsEOFWithChunkedEncoding() async throws {
        let recorder = CallbackRecorder()
        
        let chunkedResponse = """
            HTTP/1.1 200 OK\r
            Transfer-Encoding: chunked\r
            \r
            5\r
            Hello\r
            0\r
            \r
            """.data(using: .ascii)!
        
        let parser = LLHTTP(mode: .response)
        await parser.setCallbacks(headersCompleteHandler: { state in
            recorder.recordHeadersComplete(state)
        })
        
        try await parser.parse(chunkedResponse)
        
        #expect(!recorder.states.isEmpty)
        let state = recorder.states.last!
        #expect(state.messageNeedsEOF == false)
    }
    
    @Test("State remains consistent during parsing")
    func testStateConsistencyDuringParsing() async throws {
        let recorder = CallbackRecorder()
        
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(signalHandler: { signal, state in
            recorder.recordSignal(signal, state: state)
        })
        
        try await parser.parse(TestHTTP.requestWithHeaders)
        
        // All states during parsing should have consistent parser type
        for state in recorder.states {
            #expect(state.type == .request)
        }
        
        // Version should be set after version complete
        if let versionCompleteIndex = recorder.signals.firstIndex(of: .versionComplete) {
            let stateAfterVersion = recorder.states[versionCompleteIndex]
            #expect(stateAfterVersion.majorVersion > 0)
        }
    }
}
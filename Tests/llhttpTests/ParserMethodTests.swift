import Testing
import Foundation
@testable import llhttp

@Suite("Parser Methods")
struct ParserMethodTests {
    
    @Test("Parse method accepts data")
    func testParseMethod() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Should parse without throwing
        try await parser.parse(TestHTTP.minimalRequest)
    }
    
    @Test("Parse method can be called incrementally")
    func testIncrementalParsing() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(signalHandler: { signal, state in
            recorder.recordSignal(signal, state: state)
        })
        
        let data = TestHTTP.requestWithHeaders
        let chunk1 = data[0..<20]
        let chunk2 = data[20..<data.count]
        
        // Parse in chunks
        try await parser.parse(chunk1)
        try await parser.parse(chunk2)
        
        // Should have received complete message
        #expect(recorder.signals.contains(.messageComplete))
    }
    
    @Test("Pause method")
    func testPauseMethod() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Pause the parser
        await parser.pause()
        
        // Next parse should throw pause error
        await #expect(throws: LLHTTPError(code: 21, name: "HPE_PAUSED", reason: "Paused")) {
            try await parser.parse(TestHTTP.minimalRequest)
        }
    }
    
    @Test("Resume method")
    func testResumeMethod() async throws {
        let parser = LLHTTP(mode: .request)
        
        await parser.pause()
        await parser.resume()
        
        // Should be able to parse after resume
        try await parser.parse(TestHTTP.minimalRequest)
    }
    
    @Test("Resume after upgrade")
    func testResumeAfterUpgrade() async throws {
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(headersCompleteHandler: { state in
            if state.upgrade {
                return .assumeNoBodyAndPauseUpgrade
            }
            return .proceed
        })
        
        await #expect(throws: LLHTTPError(code: 22, name: "HPE_PAUSED_UPGRADE", reason: "Pause on CONNECT/Upgrade")) {
            try await parser.parse(TestHTTP.upgradeRequest)
        }
        
        // Resume after upgrade should work
        await parser.resumeAfterUpgrade()
    }
    
    @Test("Finish method for EOF")
    func testFinishMethod() async throws {
        let parser = LLHTTP(mode: .response)
        
        // Parse response without complete body
        let incompleteResponse = "HTTP/1.1 200 OK\r\n\r\nPartial".data(using: .ascii)!
        try await parser.parse(incompleteResponse)
        
        // Finish should complete the parsing
        try await parser.finish()
    }
    
    @Test("Finish method validates incomplete message")
    func testFinishValidation() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Parse incomplete request
        let incompleteRequest = "GET / HTTP/1.1\r\n".data(using: .ascii)!
        try await parser.parse(incompleteRequest)
        
        // Finish should throw error for incomplete message
        await #expect(throws: LLHTTPError.self) {
            try await parser.finish()
        }
    }
    
    @Test("Reset method")
    func testResetMethod() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(headersCompleteHandler: { state in
            recorder.recordHeadersComplete(state)
        })
        
        // Parse first request
        try await parser.parse(TestHTTP.requestWithHeaders)
        #expect(recorder.headersComplete.count == 1)
        
        // Reset parser
        await parser.reset()
        
        // Parse second request
        recorder.reset()
        try await parser.parse(TestHTTP.minimalRequest)
        #expect(recorder.headersComplete.count == 1)
    }
    
    @Test("Reset clears error state")
    func testResetClearsError() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Cause an error
        await #expect(throws: LLHTTPError.self) {
            try await parser.parse(TestHTTP.invalidData)
        }
        
        // Subsequent parses should fail with same error
        await #expect(throws: LLHTTPError.self) {
            try await parser.parse(TestHTTP.minimalRequest)
        }
        
        // Reset should clear error
        await parser.reset()
        
        // Now parsing should work
        try await parser.parse(TestHTTP.minimalRequest)
    }
    
    @Test("Multiple parse calls for single message")
    func testMultipleParseCallsPerMessage() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(signalHandler: { signal, state in
            recorder.recordSignal(signal, state: state)
        })

        // Split request into many small chunks
        let data = TestHTTP.requestWithHeaders
        var offset = 0
        
        while offset < data.count {
            let chunkSize = min(5, data.count - offset)
            let chunk = data[offset..<offset + chunkSize]
            try await parser.parse(chunk)
            offset += chunkSize
        }
        
        // Should have complete message
        #expect(recorder.signals.contains(.messageComplete))
    }
}

import Testing
import Foundation
@testable import llhttp

@Suite("Callback Forwarding")
struct CallbackForwardingTests {
    
    @Test("Signal callbacks are forwarded")
    func testSignalCallbacksForwarded() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(signalHandler: { signal, state in
            recorder.recordSignal(signal, state: state)
        })
        
        try await parser.parse(TestHTTP.requestWithHeaders)
        
        // Verify essential signal callbacks were invoked
        #expect(recorder.signals.contains(.messageBegin))
        #expect(recorder.signals.contains(.methodComplete))
        #expect(recorder.signals.contains(.urlComplete))
        #expect(recorder.signals.contains(.versionComplete))
        #expect(recorder.signals.contains(.headerFieldComplete))
        #expect(recorder.signals.contains(.headerValueComplete))
        #expect(recorder.signals.contains(.messageComplete))
    }
    
    @Test("Payload callbacks are forwarded")
    func testPayloadCallbacksForwarded() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(payloadHandler: { payload, state in
            recorder.recordPayload(payload, state: state)
        })
        
        try await parser.parse(TestHTTP.requestWithHeaders)
        
        // Verify payload callbacks received correct data
        let methodPayloads = recorder.payloads.filter { $0.0 == .method }
        #expect(!methodPayloads.isEmpty)
        #expect(String(data: methodPayloads.map { $0.1 }.reduce(Data(), +), encoding: .ascii) == "GET")
        
        let urlPayloads = recorder.payloads.filter { $0.0 == .url }
        #expect(!urlPayloads.isEmpty)
        #expect(String(data: urlPayloads.map { $0.1 }.reduce(Data(), +), encoding: .ascii) == "/path")
        
        let versionPayloads = recorder.payloads.filter { $0.0 == .version }
        #expect(!versionPayloads.isEmpty)
        
        let bodyPayloads = recorder.payloads.filter { $0.0 == .body }
        #expect(!bodyPayloads.isEmpty)
        #expect(String(data: bodyPayloads.map { $0.1 }.reduce(Data(), +), encoding: .ascii) == "Hello")
    }
    
    @Test("Headers complete callback is forwarded")
    func testHeadersCompleteCallbackForwarded() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(headersCompleteHandler: { state in
            recorder.recordHeadersComplete(state)
        })
        
        try await parser.parse(TestHTTP.requestWithHeaders)
        
        #expect(recorder.headersComplete.count == 1)
        let headers = recorder.headersComplete[0]
        #expect(headers.method == "GET")
        #expect(headers.statusCode == nil) // Request doesn't have status code
    }
    
    @Test("Response callbacks are forwarded")
    func testResponseCallbacksForwarded() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .response)
        await parser.setCallbacks(
            signalHandler: { signal, state in
                recorder.recordSignal(signal, state: state)
            },
            payloadHandler: { payload, state in
                recorder.recordPayload(payload, state: state)
            }
        )
        
        try await parser.parse(TestHTTP.responseWithHeaders)
        
        // Verify response-specific callbacks
        #expect(recorder.signals.contains(.statusComplete))
        
        let statusPayloads = recorder.payloads.filter { $0.0 == .status }
        #expect(!statusPayloads.isEmpty)
        #expect(String(data: statusPayloads.map { $0.1 }.reduce(Data(), +), encoding: .ascii) == "Not Found")
    }
    
    @Test("Chunk callbacks are forwarded")
    func testChunkCallbacksForwarded() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .response)
        await parser.setCallbacks(signalHandler: { signal, state in
            recorder.recordSignal(signal, state: state)
        })
        
        try await parser.parse(TestHTTP.multipleChunksResponse)
        
        #expect(recorder.signals.contains(.chunkHeader))
        #expect(recorder.signals.contains(.chunkComplete))
    }
    
    @Test("Reset callback is forwarded")
    func testResetCallbackForwarded() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(signalHandler: { signal, state in
            recorder.recordSignal(signal, state: state)
        })
        
        // Parse two messages in sequence
        let twoRequests = TestHTTP.minimalRequest + TestHTTP.minimalRequest
        try await parser.parse(twoRequests)
        
        #expect(recorder.signals.contains(.reset))
    }
    
    @Test("Callback return values control flow - pause")
    func testCallbackPauseControlsFlow() async throws {
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(signalHandler: { signal, state in
            if signal == .messageComplete {
                return .pause
            }
            return .proceed
        })
        
        await #expect(throws: LLHTTPError(code: 21, name: "HPE_PAUSED", reason: "on_message_complete pause")) {
            try await parser.parse(TestHTTP.minimalRequest)
        }
        
        // Resume should work
        await parser.resume()
        try await parser.parse(Data()) // Empty data to continue
    }
    
    @Test("Callback return values control flow - error")
    func testCallbackErrorControlsFlow() async throws {
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(signalHandler: { signal, state in
            if signal == .urlComplete {
                return .error
            }
            return .proceed
        })
        
        await #expect(throws: Error.self) {
            try await parser.parse(TestHTTP.minimalRequest)
        }
    }
    
    @Test("Headers complete assume no body and continue")
    func testHeadersCompleteAssumeNoBodyAndContinue() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(
            signalHandler: { signal, state in
                recorder.recordSignal(signal, state: state)
            },
            payloadHandler: { payload, state in
                recorder.recordPayload(payload, state: state)
            },
            headersCompleteHandler: { state in
                _ = recorder.recordHeadersComplete(state)
                return .assumeNoBodyAndContinue
            }
        )
        
        // Use pipelined requests without bodies
        let pipelinedRequests = """
            GET /first HTTP/1.1\r
            Host: example.com\r
            \r
            GET /second HTTP/1.1\r
            Host: example.com\r
            \r\n
            """.data(using: .ascii)!
        
        try await parser.parse(pipelinedRequests)
        
        // Verify headers complete was called for both requests
        #expect(recorder.headersComplete.count == 2)
        
        // Verify both messages completed
        let messageCompletes = recorder.signals.filter { $0 == .messageComplete }
        #expect(messageCompletes.count == 2)
        
        // No body payloads should be recorded
        let bodyPayloads = recorder.payloads.filter { $0.0 == .body }
        #expect(bodyPayloads.isEmpty)
        
        // Verify URLs for both requests
        let urlPayloads = recorder.payloads.filter { $0.0 == .url }
        #expect(urlPayloads.count == 2)
        #expect(String(data: urlPayloads[0].1, encoding: .ascii) == "/first")
        #expect(String(data: urlPayloads[1].1, encoding: .ascii) == "/second")
    }
    
    @Test("Headers complete with upgrade pause")
    func testHeadersCompleteAssumeNoBodyAndPauseUpgrade() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(
            signalHandler: { signal, state in
                recorder.recordSignal(signal, state: state)
            },
            headersCompleteHandler: { state in
                _ = recorder.recordHeadersComplete(state)
                return .assumeNoBodyAndPauseUpgrade
            }
        )
        
        // Use upgrade request
        let upgradeRequest = """
            GET /ws HTTP/1.1\r
            Host: example.com\r
            Upgrade: websocket\r
            Connection: Upgrade\r
            \r\n
            """.data(using: .ascii)!
        
        await #expect(throws: LLHTTPError(code: 22, name: "HPE_PAUSED_UPGRADE", reason: "Pause on CONNECT/Upgrade")) {
            try await parser.parse(upgradeRequest)
        }
        
        // Verify headers complete was called
        #expect(recorder.headersComplete.count == 1)
    }
    
    @Test("Headers complete with body should use proceed")
    func testHeadersCompleteWithBodyShouldUseProceed() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(
            signalHandler: { signal, state in
                recorder.recordSignal(signal, state: state)
            },
            payloadHandler: { payload, state in
                recorder.recordPayload(payload, state: state)
            },
            headersCompleteHandler: { state in
                _ = recorder.recordHeadersComplete(state)
                return .proceed  // Correct behavior for requests with bodies
            }
        )
        
        // Use request with body
        try await parser.parse(TestHTTP.requestWithHeaders)
        
        // Verify headers complete was called
        #expect(recorder.headersComplete.count == 1)
        
        // Verify message completed
        #expect(recorder.signals.contains(.messageComplete))
        
        // Body should be parsed when proceed is returned
        let bodyPayloads = recorder.payloads.filter { $0.0 == .body }
        #expect(!bodyPayloads.isEmpty)
        #expect(String(data: bodyPayloads.map { $0.1 }.reduce(Data(), +), encoding: .ascii) == "Hello")
    }
    
    @Test("All signal callbacks in order")
    func testSignalCallbackOrder() async throws {
        let recorder = CallbackRecorder()
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(signalHandler: { signal, state in
            recorder.recordSignal(signal, state: state)
        })
        
        try await parser.parse(TestHTTP.requestWithHeaders)
        
        // Verify callback order makes sense
        if let beginIndex = recorder.signals.firstIndex(of: .messageBegin),
           let completeIndex = recorder.signals.firstIndex(of: .messageComplete) {
            #expect(beginIndex < completeIndex)
        }
        
        if let methodIndex = recorder.signals.firstIndex(of: .methodComplete),
           let urlIndex = recorder.signals.firstIndex(of: .urlComplete) {
            #expect(methodIndex < urlIndex)
        }
    }
}

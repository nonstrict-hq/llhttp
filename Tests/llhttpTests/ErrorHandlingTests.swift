import Testing
import Foundation
@testable import llhttp

@Suite("Error Handling")
struct ErrorHandlingTests {
    
    @Test("Parse errors are wrapped in LLHTTPError")
    func testParseErrorsWrapped() async throws {
        let parser = LLHTTP(mode: .request)
        
        await #expect(throws: LLHTTPError.self) {
            try await parser.parse(TestHTTP.invalidData)
        }
    }
    
    @Test("Finish errors are wrapped in LLHTTPError")
    func testFinishErrorsWrapped() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Parse incomplete request
        let incompleteRequest = "GET / HTTP/1.1\r\n".data(using: .ascii)!
        try await parser.parse(incompleteRequest)
        
        await #expect(throws: LLHTTPError.self) {
            try await parser.finish()
        }
    }
    
    @Test("Error state persists")
    func testErrorStatePersists() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Cause an error
        await #expect(throws: LLHTTPError.self) {
            try await parser.parse(TestHTTP.invalidData)
        }
        
        // Subsequent parse should fail with error
        await #expect(throws: LLHTTPError.self) {
            try await parser.parse(TestHTTP.minimalRequest)
        }
    }
    
    @Test("Callback errors are handled")
    func testCallbackErrors() async throws {
        let parser = LLHTTP(mode: .request)
        await parser.setCallbacks(payloadHandler: { payload, state in
            if payload.type == .url {
                return .userError
            }
            return .proceed
        })
        
        await #expect(throws: LLHTTPError(code: 24, name: "HPE_USER", reason: nil)) {
            try await parser.parse(TestHTTP.minimalRequest)
        }
    }
    
    @Test("Pause error is distinguishable")
    func testPauseErrorDistinguishable() async throws {
        let parser = LLHTTP(mode: .request)
        await parser.pause()
        
        await #expect(throws: LLHTTPError(code: 21, name: "HPE_PAUSED", reason: "Paused")) {
            try await parser.parse(TestHTTP.minimalRequest)
        }
    }
    
    @Test("Upgrade pause error is distinguishable")
    func testUpgradePauseErrorDistinguishable() async throws {
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
    }
    
    @Test("Error contains meaningful description")
    func testErrorDescription() async throws {
        let parser = LLHTTP(mode: .request)
        
        await #expect(throws: LLHTTPError(code: 6, name: "HPE_INVALID_METHOD", reason: "Invalid method encountered")) {
            try await parser.parse(TestHTTP.invalidData)
        }
    }
    
    @Test(
        "Different invalid inputs produce different errors",
        arguments: [
            ("INVALID METHOD / HTTP/1.1\r\n\r\n", LLHTTPError(code: 6, name: "HPE_INVALID_METHOD", reason: "Invalid method encountered")),
            ("GET / HTTP/9.9\r\n\r\n", LLHTTPError(code: 9, name: "HPE_INVALID_VERSION", reason: "Invalid HTTP version")),
            ("GET\r\n\r\n", LLHTTPError(code: 6, name: "HPE_INVALID_METHOD", reason: "Expected space after method"))
        ]
    )
    func testDifferentErrorTypes(invalidInput: String, expectedError: LLHTTPError) async throws {
        let parser = LLHTTP(mode: .request)
        
        await #expect(throws: expectedError) {
            try await parser.parse(invalidInput.data(using: .ascii)!)
        }
    }
}

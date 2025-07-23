import Testing
import Foundation
@testable import llhttp

@Suite("Lenient Flags")
struct LenientFlagsTests {
    
    @Test("Lenient flags can be set")
    func testLenientFlagsCanBeSet() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Test setting individual flags
        await parser.setLenientFlags([.headers])
        #expect(await parser.lenientFlags.contains(.headers))
        
        await parser.setLenientFlags([.chunkedLength])
        #expect(await parser.lenientFlags.contains(.chunkedLength))
        
        // Test setting multiple flags
        await parser.setLenientFlags([.headers, .keepAlive, .version])
        #expect(await parser.lenientFlags.contains(.headers))
        #expect(await parser.lenientFlags.contains(.keepAlive))
        #expect(await parser.lenientFlags.contains(.version))
    }
    
    @Test("Lenient flags persist across parsing")
    func testLenientFlagsPersist() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Set flags before parsing
        await parser.setLenientFlags([.headers, .version])
        
        // Parse a request
        try await parser.parse(TestHTTP.minimalRequest)
        
        // Flags should still be set
        #expect(await parser.lenientFlags.contains(.headers))
        #expect(await parser.lenientFlags.contains(.version))
    }
    
    @Test("Lenient flags affect parsing behavior")
    func testLenientFlagsAffectParsing() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Create request with invalid character in header value (control character)
        let malformedRequest = "GET / HTTP/1.1\r\nContent-Type: text/html\u{0001}\r\n\r\n".data(using: .ascii)!
        
        // Should fail without lenient mode
        await #expect(throws: LLHTTPError(code: 10, name: "HPE_INVALID_HEADER_TOKEN", reason: "Invalid header value char")) {
            try await parser.parse(malformedRequest)
        }
        
        // Reset and try with lenient headers
        await parser.reset()
        await parser.setLenientFlags([.headers])
        
        // With lenient headers, the parser should accept the malformed header
        // and parse successfully
        try await parser.parse(malformedRequest)
    }
    
    @Test("All lenient flag options")
    func testAllLenientFlagOptions() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Test that all flag options can be set
        let allFlags: LLHTTP.LenientFlags = [
            .headers,
            .chunkedLength,
            .keepAlive,
            .transferEncoding,
            .version,
            .dataAfterClose,
            .optionalLFAfterCR,
            .optionalCRLFAfterChunk,
            .optionalCRBeforeLF,
            .spacesAfterChunkSize
        ]
        
        await parser.setLenientFlags(allFlags)
        #expect(await parser.lenientFlags == allFlags)
    }
    
    @Test("Lenient flags can be cleared")
    func testLenientFlagsCanBeCleared() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Set some flags
        await parser.setLenientFlags([.headers, .version])
        let flags = await parser.lenientFlags
        #expect(!flags.isEmpty)
        
        // Clear flags
        await parser.setLenientFlags([])
        let clearedFlags = await parser.lenientFlags
        #expect(clearedFlags.isEmpty)
    }
    
    @Test("Lenient flags survive reset")
    func testLenientFlagsSurviveReset() async throws {
        let parser = LLHTTP(mode: .request)
        
        // Set flags
        await parser.setLenientFlags([.headers, .keepAlive])
        
        // Reset parser
        await parser.reset()
        
        // Flags should still be set
        #expect(await parser.lenientFlags.contains(.headers))
        #expect(await parser.lenientFlags.contains(.keepAlive))
    }
}

import Testing
@testable import llhttp

/// Basic sanity check that the wrapper can be instantiated and used
@Test func wrapperSanityCheck() async throws {
    let parser = LLHTTP(mode: .request)
    let minimalRequest = "GET / HTTP/1.1\r\n\r\n".data(using: .ascii)!
    try await parser.parse(minimalRequest)
}

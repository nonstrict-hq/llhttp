# llhttp — HTTP Parser for Swift 

_A parser for HTTP messages in Swift, it parses both requests and responses by wrapping [llhttp](https://github.com/nodejs/llhttp), the HTTP parser used in [Node.js](https://nodejs.org)._

This library provides **incremental HTTP parsing**, allowing you to parse either HTTP requests and responses as data arrives from the network without having to frame complete messages.

## Key Features

- **Complete HTTP Support**: Handles requests, responses, keep-alive, chunked encoding, protocol upgrades
- **Incremental Parsing**: Pass in HTTP data as it arrives, perfect for streaming scenarios
- **High Performance**: Built on llhttp, one of the fastest and battle-tested HTTP parsers available
- **Multiple Abstraction Levels**: Get every low-level llhttp event or get completely parsed HTTP messages
- **Swift Concurrency Support**: Thread-safe actors by default, with preconcurrency fallback options for older code

## Installation

Add this package to your Swift Package Manager dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/nonstrict-hq/llhttp", from: "1.0.0")
]
```

## Choosing the Right API Level

- **LLHTTP**: Thin wrapper around the C library llhttp that emits events and doesn't keep data in memory.
- **HTTPMessagesParser**: Receive complete HTTP requests/responses in a Swift async streams, completely with the body in memory.

## Quick Start

### For Complete HTTP Messages (Easiest)

If you just want to handle complete HTTP messages:

```swift
import llhttp

let parser = HTTPMessagesParser(mode: HTTPMessage.Both.self)

// Keep reading data from the network connection and parse it
Task {
    do {
        while true {
            let content = try await connection.receive(atMost: 512).content
            try await parser.parse(content)
        }
    } catch {
        try await parser.finish()
    }
}

// When a complete HTTP message is received handle it
Task {
    for await message in parser.completedMessages {
        // TODO: Handle incomming HTTP message
    }
}
```

_Note: This parser needs to keep the whole HTTP message including body in memory and therefore won't work to receive large requests/responses like big files for example. You will run out of memory in that case._

### For Event-Driven Parsing (More control)

For fine-grained control over parsing events:

```swift
let parser = LLHTTP(mode: .both)

await parser.setCallbacks { signal, state in
        // TODO: Handle signal
        return .proceed
    } payloadHandler: { payload, state in
        // TODO: Handle payload
        return .proceed
    } headersCompleteHandler: { state in
        // TODO: Handle headers complete
        return .proceed
    }

try await parser.parse(httpData)
```

_Note: This is a one-on-one wrapper around the llhttp C-implementation._

## Advanced Features

### Parser Modes
- `.request` - Parse only HTTP requests
- `.response` - Parse only HTTP responses  
- `.both` - Auto-detect based on first message

### Lenient Parsing Flags
:warning: **Security Warning**: Lenient flags can expose you to HTTP request smuggling and other attacks. Use with extreme caution.

For compatibility with legacy systems you can turn on lenient flags so incorrect HTTP messages are accepted.

### Preconcurrency

When using callback based networking APIs or in older codebases it might be impractical to use actors and make your callback closurus Sendable. Therefore there are also `Preconcurrency` variants of both `LLHTTP` and  `HTTPMessagesParser`. These are non-sendable and non-reentrant safe, but also much more convenient to use when you have callback based APIs that deliver the HTTP stream to you.

## License

This Swift wrapper created by [Nonstrict B.V.](https://nonstrict.eu) and licensed under the [MIT License](License.md).

The [llhttp C library](https://github.com/nodejs/llhttp) is created by [Fedor Indutny](https://github.com/indutny) and licensed under the [MIT License](Sources/Cllhttp/LICENSE).

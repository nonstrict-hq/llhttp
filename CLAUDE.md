# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Swift Package Manager (SPM) library providing Swift bindings for llhttp, the HTTP parser used in Node.js. The package wraps the C library with Swift types and provides multiple abstraction levels to the user.

- `LLHTTP.Preconcurrency`: Direct Swift wrapper around C implementation
- `LLHTTP`: Swift Concurrency-safe actor-based interface
- `HTTPMessagesParser`: Higher-level abstraction that yields complete HTTP messages via callbacks and AsyncStreams

## Platform Requirements

The library supports the following platforms:
- **iOS**: 13.0+
- **macOS**: 10.15+
- **macCatalyst**: 13.0+
- **tvOS**: 13.0+
- **visionOS**: 1.0+
- **watchOS**: 6.0+

**Note**: The `HTTPMessagesParser` class requires higher minimum versions due to its use of `OSAllocatedUnfairLock`:
- **iOS**: 16.0+
- **macOS**: 13.0+
- **tvOS**: 16.0+
- **watchOS**: 9.0+

The lower-level `LLHTTP` and `LLHTTP.Preconcurrency` APIs are available on all supported platform versions listed above.

## Commands

### Build and Test
- **Build**: `swift build --build-tests`
- **Run all tests**: `swift test`
- **Run specific test**: `swift test --filter <TestName>`

## Code and File Structure

### `Sources/Cllhttp`
This directory contains the vendored C `llhttp` source code. It is the lowest layer of the library and must not be modified directly. Changes should only occur when updating to a new version of the upstream C library.

### `Sources/llhttp`
This directory contains all the Swift code, organized by functionality. The core architectural pattern is to define a central type and extend it with logically grouped functionality in separate files.

- **`LLHTTP.swift`**: The core `actor` that wraps the C parser, providing the primary async interface.
- **`LLHTTP+Preconcurrency.swift`**: Defines the `LLHTTP.Preconcurrency` type, a non-concurrency-safe, direct Swift wrapper around the C implementation. This is for users who need to manage thread safety manually for performance reasons.
- **`LLHTTP+*.swift`**: Extensions that add functionality to the `LLHTTP` actor. This is the primary organizational convention.
    - `LLHTTP+Events.swift`: Manages the mapping of C callbacks to Swift async streams.
    - `LLHTTP+State.swift`: Handles state management.
    - `LLHTTP+LenientFlags.swift`: Manages lenient parsing flags.
    - `LLHTTP+Mode.swift`: Defines the parser mode enum (both, request, response) for initialization.
- **`HTTPMessagesParser.swift`**: A higher-level API that consumes events from `LLHTTP` and produces complete `HTTPMessage` objects. It offers both a concurrency-safe implementation and a `Preconcurrency` variant.
- **`HTTPMessage.swift`**: Defines the `HTTPRequest` and `HTTPResponse` data models.
- **`HTTPMessageBuilder.swift`**: An internal helper responsible for assembling message objects from parser events.
- **`LLHTTPError.swift`**: Defines the typed errors thrown by the Swift layer.
- **`Array+Subscripting.swift`**: Internal utility providing convenient subscript access for first/last array elements.

## Testing Approach

The project follows a Test-Driven Development (TDD) methodology. New features or bug fixes should be accompanied by tests.

### Testing Framework
- **Swift Testing**: This project uses the modern Swift Testing framework (not XCTest)
- **Assertions**: Use `#expect()` for soft checks and `#require()` for critical preconditions that should abort the test if they fail
- **Error Testing**: Use `#expect(throws: MyError.self) { ... }` to test for thrown errors

### Test Structure  
- **File Mapping**: A source file `Sources/llhttp/X.swift` is typically tested by a corresponding `Tests/llhttpTests/XTests.swift`
- **Test Suites**: Tests are organized using `@Suite` attributes and `@Test` functions
- **Test Data**: The `TestHelpers.swift` file contains sample HTTP messages and utilities for testing

## Agent Documentation

Guidance for AI agents on project conventions, such as the testing framework and its usage, can be found in the `Docs/Agent/` directory.

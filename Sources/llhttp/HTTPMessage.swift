//
//  HTTPMessage.swift
//  llhttp
//
//  Created by Mathijs Kadijk on 30/07/2025.
//

import Foundation

/// A type that can represent HTTP messages created from parsed HTTP data.
///
/// This protocol defines the contract for HTTP message types that can be constructed
/// from the internal message builder after parsing HTTP data.
public protocol HTTPMessageType: Sendable {
    /// The parser mode this message type corresponds to.
    static var mode: LLHTTP.Mode { get }
    
    /// Creates an HTTP message from the accumulated parsed data.
    ///
    /// - Parameter builder: The builder containing all parsed HTTP components
    /// - Returns: A new message instance, or `nil` if the builder data doesn't match this message type
    init?(builder: AnyHTTPMessageBuilder)
}

/// Container for HTTP message types including requests, responses, and unified message handling.
///
/// This enum provides different representations of HTTP messages:
/// - `Request`: For HTTP request messages
/// - `Response`: For HTTP response messages  
/// - `Both`: For handling either request or response messages in a unified way
public enum HTTPMessage {
    /// A unified HTTP message type that can represent either a request or response.
    ///
    /// Use this type when you need to handle either HTTP requests and responses
    /// in the same parsing context without knowing the message stream type in advance.
    public enum Both: HTTPMessageType {
        /// The `LLHTTP.Mode` to use when parsing messages of this type.
        public static let mode: LLHTTP.Mode = .both

        /// An HTTP request message.
        case request(Request)
        
        /// An HTTP response message.
        case response(Response)

        public init?(builder: AnyHTTPMessageBuilder) {
            if let request = Request(builder: builder) {
                self = .request(request)
            } else if let response = Response(builder: builder) {
                self = .response(response)
            } else {
                return nil
            }
        }

        /// The HTTP protocol name (typically "HTTP").
        public var `protocol`: String {
            switch self {
            case .request(let request):
                return request.protocol
            case .response(let response):
                return response.protocol
            }
        }
        
        /// The HTTP version (e.g., "1.1", "2.0").
        public var version: String {
            switch self {
            case .request(let request):
                return request.version
            case .response(let response):
                return response.version
            }
        }
        
        /// HTTP headers as a dictionary mapping header names to arrays of values.
        ///
        /// Each header can have multiple values if it occured multiple times in the HTTP message.
        public var headers: [String: [String]] {
            switch self {
            case .request(let request):
                return request.headers
            case .response(let response):
                return response.headers
            }
        }
        
        /// The HTTP message body.
        public var body: Body {
            switch self {
            case .request(let request):
                return request.body
            case .response(let response):
                return response.body
            }
        }

        /// The HTTP method (e.g., "GET", "POST") if this is a request message.
        ///
        /// - Returns: The method string for requests, or `nil` for responses.
        public var method: String? {
            switch self {
            case .request(let request):
                return request.method
            case .response:
                return nil
            }
        }
        
        /// The request URL if this is a request message.
        ///
        /// - Returns: The URL string for requests, or `nil` for responses.
        public var url: String? {
            switch self {
            case .request(let request):
                return request.url
            case .response:
                return nil
            }
        }

        /// The HTTP status code and reason phrase if this is a response message.
        ///
        /// - Returns: The status string for responses (e.g., "200 OK"), or `nil` for requests.
        public var status: String? {
            switch self {
            case .request:
                return nil
            case .response(let response):
                return response.status
            }
        }
    }

    /// Represents a complete HTTP request message.
    ///
    /// Contains all components of an HTTP request including method, URL, headers, and body.
    public struct Request: HTTPMessageType {
        /// The `LLHTTP.Mode` to use when parsing messages of this type.
        public static let mode: LLHTTP.Mode = .request

        /// The HTTP method (e.g., "GET", "POST", "PUT").
        public let method: String
        
        /// The request URL or path.
        public let url: String
        
        /// The HTTP protocol name (typically "HTTP").
        public let `protocol`: String
        
        /// The HTTP version (e.g., "1.1", "2.0").
        public let version: String
        
        /// HTTP headers as a dictionary mapping header names to arrays of values.
        ///
        /// Each header can have multiple values if it occured multiple times in the HTTP message.
        public let headers: [String: [String]]
        
        /// The request body.
        public let body: Body

        public init?(builder: AnyHTTPMessageBuilder) {
            guard builder.type == .request else { return nil }

            guard let method = builder.headerValues[.method]?.first else { return nil }
            self.method = String(decoding: method, as: UTF8.self)

            guard let url = builder.headerValues[.url]?.first else { return nil }
            self.url = String(decoding: url, as: UTF8.self)

            guard let `protocol` = builder.headerValues[.protocol]?.first else { return nil }
            self.protocol = String(decoding: `protocol`, as: UTF8.self)

            guard let version = builder.headerValues[.version]?.first else { return nil }
            self.version = String(decoding: version, as: UTF8.self)

            let headerPairs = zip(
                builder.headerValues[.headerField, default: []].map { String(decoding: $0, as: UTF8.self) },
                builder.headerValues[.headerValue, default: []].map { String(decoding: $0, as: UTF8.self) }
            )
            self.headers = Dictionary(grouping: headerPairs) { $0.0 }
                .mapValues { $0.map { $0.1 } }
                .filter { !($0.key.isEmpty && $0.value.allSatisfy(\.isEmpty)) }

            self.body = Body(chunkValues: builder.chunkValues)
        }
    }

    /// Represents a complete HTTP response message.
    ///
    /// Contains all components of an HTTP response including status, headers, and body.
    /// This struct is immutable and created from parsed HTTP response data.
    public struct Response: HTTPMessageType {
        public static let mode: LLHTTP.Mode = .response

        /// The HTTP protocol name (typically "HTTP").
        public let `protocol`: String
        
        /// The HTTP version (e.g., "1.1", "2.0").
        public let version: String
        
        /// The HTTP status code and reason phrase (e.g., "200 OK", "404 Not Found").
        public let status: String
        
        /// HTTP headers as a dictionary mapping header names to arrays of values.
        ///
        /// Each header can have multiple values if it occured multiple times in the HTTP message.
        public let headers: [String: [String]]
        
        /// The response body.
        public let body: Body

        public init?(builder: AnyHTTPMessageBuilder) {
            guard builder.type == .response else { return nil }

            guard let `protocol` = builder.headerValues[.protocol]?.first else { return nil }
            self.protocol = String(decoding: `protocol`, as: UTF8.self)

            guard let version = builder.headerValues[.version]?.first else { return nil }
            self.version = String(decoding: version, as: UTF8.self)

            guard let status = builder.headerValues[.status]?.first else { return nil }
            self.status = String(decoding: status, as: UTF8.self)

            let headerPairs = zip(
                builder.headerValues[.headerField, default: []].map { String(decoding: $0, as: UTF8.self) },
                builder.headerValues[.headerValue, default: []].map { String(decoding: $0, as: UTF8.self) }
            )
            self.headers = Dictionary(grouping: headerPairs) { $0.0 }
                .mapValues { $0.map { $0.1 } }
                .filter { !($0.key.isEmpty && $0.value.allSatisfy(\.isEmpty)) }

            self.body = Body(chunkValues: builder.chunkValues)
        }
    }

    /// Represents a single chunk in HTTP chunked transfer encoding.
    ///
    /// Each chunk contains data and optional chunk extensions.
    /// Chunk extensions are additional metadata that can be included with each chunk.
    public struct Chunk: Sendable, Equatable {
        /// The chunk's data payload.
        public let data: Data
        
        /// Chunk extensions as a dictionary mapping extension names to arrays of values.
        ///
        /// Extensions provide additional per-chunk metadata.
        /// Each header can have multiple values if it occured multiple times in the HTTP message.
        public let extensions: [String: [String]]
    }

    /// Represents the body of an HTTP message.
    ///
    /// HTTP message bodies can be in different formats:
    /// - Single contiguous data for standard requests/responses
    /// - Chunked transfer encoding with multiple chunks and extensions
    /// - Empty for messages without body content
    public enum Body: Sendable, Equatable {
        /// A single contiguous body with all data.
        case single(Data)
        
        /// A chunked body with multiple chunks, each potentially having extensions.
        case chunked([Chunk])
        
        /// An empty body with no content.
        case empty

        internal init(chunkValues: [[LLHTTP.PayloadType: [Data]]]) {
            let chunks = chunkValues.compactMap { chunkValue -> HTTPMessage.Chunk? in
                let extensionPairs = zip(
                    chunkValue[.chunkExtensionName, default: []].map { String(decoding: $0, as: UTF8.self) },
                    chunkValue[.chunkExtensionValue, default: []].map { String(decoding: $0, as: UTF8.self) }
                )
                let extensions = Dictionary(grouping: extensionPairs) { $0.0 }
                    .mapValues { $0.map { $0.1 } }
                    .filter { !($0.key.isEmpty && $0.value.allSatisfy(\.isEmpty)) }

                let bodyData = chunkValue[.body, default: []].first ?? Data()

                if extensions.isEmpty && bodyData.isEmpty {
                    return nil
                } else {
                    return HTTPMessage.Chunk(data: bodyData, extensions: extensions)
                }
            }

            if chunks.count > 1 || chunks.first?.extensions.isEmpty == false {
                self = .chunked(chunks)
            } else if let singleChunk = chunks.first {
                self = .single(singleChunk.data)
            } else {
                self = .empty
            }
        }

        /// The complete body data as a single `Data` object.
        ///
        /// For chunked bodies, this concatenates all chunk data together.
        /// For single bodies, this returns the data directly.
        /// For empty bodies, this returns empty `Data`.
        public var data: Data {
            switch self {
            case .single(let data):
                return data
            case .chunked(let chunks):
                let totalSize = chunks.reduce(0) { $0 + $1.data.count }
                return chunks.reduce(into: Data(capacity: totalSize)) { result, chunk in
                    result.append(chunk.data)
                }
            case .empty:
                return Data()
            }
        }
    }
}

//
//  LLHTTP+Mode.swift
//  llhttp
//
//  Created by Mathijs Kadijk on 24/07/2025.
//

import Foundation
internal import Cllhttp

extension LLHTTP {
    /// Whether the parser should parse requests, responses or choose based on the first input read.
    public enum Mode: UInt32, Sendable {
        /// Initialize the parser in `both`mode, meaning that it will select between `request` and `response` parsing automatically while reading the first input.
        case both = 0
        /// Initialize the parser to parse requests.
        case request = 1
        /// Initialize the parser to parse responses.
        case response = 2

        var type: llhttp_type_t {
            llhttp_type_t(rawValue: rawValue)
        }
    }
}

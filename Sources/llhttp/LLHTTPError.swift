//
//  LLHTTPError.swift
//  llhttp
//
//  Created by Mathijs Kadijk on 23/07/2025.
//

public struct LLHTTPError: Error, Equatable, Sendable {
    /// Internal LLHTTP error number.
    let code: UInt32
    /// Short name of the error.
    let name: String
    /// Reason the error occured or where it originated from.
    let reason: String?
}

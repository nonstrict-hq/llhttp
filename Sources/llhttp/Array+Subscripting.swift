//
//  Array+Subscripting.swift
//  llhttp
//
//  Created by Nonstrict on 29/07/2025.
//

import Foundation

internal enum Position {
    case first
    case last
}

internal extension Array {
    subscript(position: Position) -> Element? {
        get {
            if isEmpty { return nil }
            switch position {
            case .first:
                return self[0]
            case .last:
                return self[count-1]
            }
        }
        set {
            if isEmpty { return }
            guard let newValue else { return }
            switch position {
            case .first:
                self[0] = newValue
            case .last:
                self[count-1] = newValue
            }
        }
    }
}

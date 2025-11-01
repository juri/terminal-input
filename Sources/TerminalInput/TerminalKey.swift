//
//  TerminalKey.swift
//
//  Created by Juri Pakaste on 30.10.2025.
//

public enum KeyCommand: Sendable {
    case backspace
    case backtab
    case character(Character)
    case delete
    case deleteToEnd
    case deleteToStart
    case down
    case esc
    case fileSeparator
    case groupSeparator
    case left
    case moveToEnd
    case moveToStart
    case null
    case recordSeparator
    case `return`
    case right
    case suspend
    case tab
    case terminate
    case transpose
    case unitSeparator
    case up
    case up
}

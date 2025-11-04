//
//  TerminalKey.swift
//
//  Created by Juri Pakaste on 30.10.2025.
//

/// `KeyCommand` reprents keys read from a terminal at a slightly higher level than ``KeyInput``.
///
/// It has the same values ``KeyInput``, but it contains named values for line-editing commands.
public enum KeyCommand: Sendable {
    case backspace
    case backtab
    case character(Character)
    case controlSequence(String)
    case delete
    case deleteToEnd
    case deleteToStart
    case down
    case esc
    case escapeSequence(String)
    case function(Int)
    case left
    case moveBackwardWord
    case moveForwardWord
    case moveToEnd
    case moveToStart
    case `return`
    case right
    case suspend
    case tab
    case terminate
    case transpose
    case up

    public init(keyInput: KeyInput) {
        switch keyInput {
        case .backtab: self = .backtab
        case .byte(0x01): self = .moveToStart
        case .byte(0x03): self = .terminate
        case .byte(0x04): self = .delete
        case .byte(0x05): self = .moveToEnd
        case .byte(0x09): self = .tab
        case .byte(0x0B): self = .deleteToEnd
        case .byte(0x0D): self = .return
        case .byte(0x14): self = .transpose
        case .byte(0x15): self = .deleteToStart
        case .byte(0x1A): self = .suspend
        case .byte(0x1B): self = .esc
        case .byte(0x7F): self = .backspace
        case let .byte(b): self = .character(Character(Unicode.Scalar(b)))
        case let .character(c): self = .character(c)
        case .controlSequence("15~"): self = .function(5)
        case .controlSequence("17~"): self = .function(6)
        case .controlSequence("18~"): self = .function(7)
        case .controlSequence("19~"): self = .function(8)
        case .controlSequence("20~"): self = .function(9)
        case .controlSequence("21~"): self = .function(10)
        case .controlSequence("23~"): self = .function(11)
        case .controlSequence("24~"): self = .function(12)
        case let .controlSequence(s): self = .controlSequence(s)
        case .escapeSequence("b"): self = .moveBackwardWord
        case .escapeSequence("f"): self = .moveForwardWord
        case .escapeSequence("OP"): self = .function(1)
        case .escapeSequence("OQ"): self = .function(2)
        case .escapeSequence("OR"): self = .function(3)
        case .escapeSequence("OS"): self = .function(4)

        case let .escapeSequence(s): self = .escapeSequence(s)
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .up: self = .up
        }
    }
}

/// `KeyInput` is a single value read from a terminal.
public enum KeyInput: Sendable {
    case backtab
    case byte(UInt8)
    case character(Character)
    case controlSequence(String)
    case escapeSequence(String)
    case down
    case left
    case right
    case up
}

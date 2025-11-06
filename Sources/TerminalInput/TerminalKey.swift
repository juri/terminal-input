//
//  TerminalKey.swift
//
//  Created by Juri Pakaste on 30.10.2025.
//

/// Keyboard modifiers that can be applied to function keys.
public enum Modifier: Sendable {
    /// The control key.
    case control
    /// The alt key.
    case alt
    /// The shift key.
    case shift
    /// The meta key.
    case meta
}

/// `KeyCommand` reprents keys read from a terminal at a slightly higher level than ``KeyInput``.
///
/// It has the same values ``KeyInput``, but it contains named values for line-editing commands.
public enum KeyCommand: Sendable, Hashable {
    case backspace
    case backtab
    case character(Character)
    case delete
    case deleteBackwardWord
    case deleteToEnd
    case deleteToStart
    case down(Set<Modifier>)
    case esc
    case escapeSequence(String)
    case left(Set<Modifier>)
    case moveToEnd
    case moveToStart
    case `return`
    case right(Set<Modifier>)
    case suspend
    case tab
    case terminate
    case transpose
    case up(Set<Modifier>)

    public init(keyInput: KeyInput) {
        switch keyInput {
        case .backtab: self = .backtab
        case .byte(0x01): self = .moveToStart
        case .byte(0x03): self = .terminate
        case .byte(0x04): self = .delete
        case .byte(0x05): self = .moveToEnd
        case .byte(0x08): self = .deleteBackwardWord
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
        case .escapeSequence("\(Code.esc)b"): self = .left([.alt])
        case .escapeSequence("\(Code.esc)f"): self = .right([.alt])
        case let .escapeSequence(s): self = parseEscapeSequence(s: s)
        case .down: self = .down([])
        case .left: self = .left([])
        case .right: self = .right([])
        case .up: self = .up([])
        }
    }
}

/// `KeyInput` is a single value read from a terminal.
public enum KeyInput: Sendable, Hashable {
    case backtab
    case byte(UInt8)
    case character(Character)
    case escapeSequence(String)
    case down
    case left
    case right
    case up
}

enum Code {
    static let esc = "\u{001B}" as String
}

func parseEscapeSequence(s: String) -> KeyCommand {
    var ss = s[...]
    guard ss.hasPrefix(Code.esc) else { return .escapeSequence(s) }
    ss.removeFirst()

    if ss == "b" { return .left([.alt]) }
    if ss == "f" { return .right([.alt]) }

    if ss.hasPrefix("[") {
        ss.removeFirst()
        guard !ss.isEmpty else { return .escapeSequence(s) }
    }

    while let first = ss.first, first.isASCII && first.isNumber {
        // skip initial number
        ss.removeFirst()
    }

    guard !ss.isEmpty else { return .escapeSequence(s) }

    if ss.hasPrefix(";") {
        ss.removeFirst()
    }

    // read number after ; to get the modifiers
    var modifiersStart: String.Index? = nil
    while let first = ss.first, first.isASCII && first.isNumber {
        // skip initial number
        if modifiersStart == nil {
            modifiersStart = ss.startIndex
        }
        ss.removeFirst()
    }

    let modifiers: Substring? =
        if let modifiersStart {
            s[modifiersStart..<ss.startIndex]
        } else {
            nil
        }

    guard let modifiers else { return .escapeSequence(s) }

    let modifiersValue = Int(modifiers)
    let modifiersSet: Set<Modifier> =
        switch modifiersValue {
        case 2: [.shift]
        case 3: [.alt]
        case 4: [.shift, .alt]
        case 5: [.control]
        case 6: [.shift, .control]
        case 7: [.alt, .control]
        case 8: [.shift, .alt, .control]
        case 9: [.meta]
        case 10: [.meta, .shift]
        case 11: [.meta, .alt]
        case 12: [.meta, .alt, .shift]
        case 13: [.meta, .control]
        case 14: [.meta, .control, .shift]
        case 15: [.meta, .control, .alt]
        case 16: [.meta, .control, .alt, .shift]
        default: []
        }

    switch ss {
    case "D": return .left(modifiersSet)
    case "C": return .right(modifiersSet)
    case "A": return .up(modifiersSet)
    case "B": return .down(modifiersSet)
    default: return .escapeSequence(s)
    }
}

import Testing

@testable import TerminalInput

@Suite struct EscapeSequenceParseTests {
    @Test func testEmpty() {
        #expect(parseEscapeSequence(s: "") == .escapeSequence(""))
    }

    @Test func testOnlyEscape() {
        #expect(parseEscapeSequence(s: "\u{1B}") == .escapeSequence("\u{1B}"))
    }

    @Test(arguments: [
        ("\u{1B}b", KeyCommand.left([.alt])),
        ("\u{1B}f", KeyCommand.right([.alt])),
    ]) func testPlainArrows(_ input: String, _ command: KeyCommand) {
        #expect(parseEscapeSequence(s: input) == command)
    }

    @Test(arguments: [
        ("\u{1B}[1;2D", KeyCommand.left([.shift])),
        ("\u{1B}[1;3D", KeyCommand.left([.alt])),
        ("\u{1B}[1;4D", KeyCommand.left([.alt, .shift])),
        ("\u{1B}[1;5D", KeyCommand.left([.control])),
        ("\u{1B}[1;6A", KeyCommand.up([.control, .shift])),
        ("\u{1B}[1;7A", KeyCommand.up([.control, .alt])),
        ("\u{1B}[1;8C", KeyCommand.right([.control, .shift, .alt])),
        ("\u{1B}[1;9C", KeyCommand.right([.meta])),
        ("\u{1B}[1;10B", KeyCommand.down([.meta, .shift])),
        ("\u{1B}[1;11B", KeyCommand.down([.meta, .alt])),
    ]) func testModifierArrows(_ input: String, _ command: KeyCommand) {
        #expect(parseEscapeSequence(s: input) == command)
    }
}

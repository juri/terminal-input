[![Build](https://github.com/juri/terminal-input/actions/workflows/ci.yml/badge.svg)](https://github.com/juri/terminal-input/actions/workflows/ci.yml)
[![Build](https://github.com/juri/terminal-input/actions/workflows/format.yml/badge.svg)](https://github.com/juri/terminal-input/actions/workflows/format.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fjuri%2Fterminal-input%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/juri/terminal-input)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fjuri%2Fterminal-input%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/juri/terminal-input)

# terminal-input

This is a Swift package for reading keyboard input from a terminal emulator. It has been extracted and expanded from [tui-fuzzy-finder].

`terminal-input` allows you to read single characters, control keys and control sequences from the terminal.

[tui-fuzzy-finder]: https://github.com/juri/tui-fuzzy-finder.git

## Usage

```swift
import TerminalInput

try await KeyReader.inRawMode(fileHandle: ttyHandle) { rawReader in
    loop: for await keyInput in rawReader.keyStream() {
        let keyCommand = KeyCommand(keyInput: keyInput)
        switch keyCommand {
        case .character("Q"):
            print("Q pressed, quitting")
            break loop
        case .up:
            print("Up pressed")
        default:
            print("Received key: \(keyCommand)")
        }
    }
}
```

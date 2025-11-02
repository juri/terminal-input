//
//  Runner.swift
//
//  Created by Juri Pakaste on 30.10.2025.
//

import Foundation
import TerminalInput

@main
struct Runner {
    public static func main() async throws {
        guard let ttyHandle = FileHandle(forReadingAtPath: "/dev/tty") else {
            return
        }

        print("terminal-input runner started. Type Q to quit.")
        print("\u{001B}[?25l") // hide cursor

        defer {
            print("\u{001B}[?25h") // show cursor
        }

        try await KeyReader.inRawMode(fileHandle: ttyHandle) { rawReader in
            loop: for await keyInput in rawReader.keyStream() {
                let keyCommand = KeyCommand(keyInput: keyInput)
                switch keyCommand {
                case .character("Q"):
                    print("Q pressed, quitting")
                    break loop
                default:
                    print("Received key: \(keyCommand)")
                    print("\u{001B}[0G", terminator: "") // move to line start
                }
            }
        }
    }
}

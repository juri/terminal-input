import Foundation
import Synchronization

@MainActor
public enum KeyReader {
    public static func readKeys(
        fileHandle: FileHandle,
        to callback: @escaping @Sendable (KeyInput) -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            let bufferSize = 32
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            var bufferPoint = 0
            loop: while !Task.isCancelled {
                precondition(bufferPoint >= 0)
                precondition(bufferPoint < bufferSize)
                let key: KeyInput?
                if bufferPoint < bufferSize {
                    var inputBuffer = [UInt8](repeating: 0, count: bufferSize - bufferPoint)
                    let bytesRead = read(fileHandle.fileDescriptor, &inputBuffer, bufferSize - bufferPoint)
                    for byteIndex in 0..<bytesRead {
                        let byte = inputBuffer[byteIndex]
                        let targetIndex = bufferPoint + byteIndex
                        buffer[targetIndex] = byte
                    }
                    bufferPoint += bytesRead
                }

                guard bufferPoint > 0 else {
                    continue loop
                }
                if bufferPoint == 1 {
                    key = .byte(buffer[0])
                    consumeStart(array: &buffer, bytes: 1)
                    bufferPoint -= 1
                } else if bufferPoint == 3 {
                    var _key: KeyInput? = nil
                    switch (buffer[0], buffer[1], buffer[2]) {
                    case (0x1B, 0x5B, 0x41): _key = .up
                    case (0x1B, 0x5B, 0x42): _key = .down
                    case (0x1B, 0x5B, 0x43): _key = .right
                    case (0x1B, 0x5B, 0x44): _key = .left
                    case (0x1B, 0x5B, 0x5A): _key = .backtab
                    default: break
                    }

                    if let _key {
                        consumeStart(array: &buffer, bytes: 3)
                        bufferPoint -= 3
                        key = _key
                    } else if var str = String(bytes: buffer[0..<bufferPoint], encoding: .utf8), str.count > 0 {
                        let first = str.removeFirst()
                        let count = first.utf8.count
                        consumeStart(array: &buffer, bytes: count)
                        bufferPoint -= count
                        key = .character(first)
                    } else {
                        key = nil
                    }

                } else if bufferPoint > 2 && buffer[0] == 0x1B && buffer[1] == 0x5B {
                    // CSI code, grab everything until we run out of buffered values or encounter a character
                    // in the range 0x40…0x7E.
                    parseControlSequence: do {
                        for i in 2..<bufferPoint {
                            if (0x40...0x7E).contains(buffer[i]) {
                                guard let str = String(bytes: buffer[2...i], encoding: .utf8) else {
                                    // Failed to parse the control sequence, just throw everything away
                                    for i in 0 ..< bufferSize {
                                        buffer[i] = 0
                                    }
                                    bufferPoint = 0
                                    key = nil
                                    continue loop
                                }
                                key = .controlSequence(str)
                                consumeStart(array: &buffer, bytes: i + 1)
                                bufferPoint -= i + 1
                                break parseControlSequence
                            }
                        }
                        key = nil
                    }
                } else if var str = String(bytes: buffer[0..<bufferPoint], encoding: .utf8),
                    str.count > 0
                {
                    let first = str.removeFirst()
                    let count = first.utf8.count
                    consumeStart(array: &buffer, bytes: count)
                    bufferPoint -= count
                    key = .character(first)
                } else if bufferPoint == bufferSize {
                    print("buffer was full but we don't know what to with it, clear it")
                    // buffer is already full, and we apparently didn't know what to do with it.
                    for i in 0 ..< bufferSize {
                        buffer[i] = 0
                    }
                    bufferPoint = 0
                    key = nil
                } else {
                    key = nil
                }

                if let key {
                    callback(key)
                }
            }
        }
    }

    public static func keyStream(
        fileHandle: FileHandle
    ) -> AsyncStream<KeyInput> {
        let (stream, continuation) = AsyncStream<KeyInput>.makeStream()

        let task = self.readKeys(fileHandle: fileHandle) { result in
            continuation.yield(result)
        }
        continuation.onTermination = { _ in
            task.cancel()
        }

        return stream
    }

    public struct CallFailure: Error {
        public let call: Call
        public let errno: Int32

        public enum Call: Sendable {
            case tcgetattr
            case tcsetattr
        }
    }

    public static func inRawMode<T>(
        fileHandle: FileHandle,
        _ body: (RawKeyReader) async -> T
    ) async throws(CallFailure) -> T {
        let originalTermios = try self.setRaw(fileHandle: fileHandle)
        let rawReader = RawKeyReader(fileHandle: fileHandle)
        let value = await body(rawReader)
        try self.unsetRaw(fileHandle: fileHandle, originalTermios: originalTermios)
        return value
    }

    public static func setRaw(fileHandle: FileHandle) throws(CallFailure) -> termios {
        var originalTermios = termios()

        if tcgetattr(fileHandle.fileDescriptor, &originalTermios) == -1 {
            throw CallFailure(call: .tcgetattr, errno: errno)
        }

        var raw = originalTermios

        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)

        withUnsafeMutablePointer(to: &raw.c_cc) {
            $0.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { $0[Int(VMIN)] = 1 }
        }

        if tcsetattr(fileHandle.fileDescriptor, TCSAFLUSH, &raw) < 0 {
            throw CallFailure(call: .tcsetattr, errno: errno)
        }

        return originalTermios
    }

    public static func unsetRaw(
        fileHandle: FileHandle,
        originalTermios: termios,
    ) throws(CallFailure) {
        var originalTermios = originalTermios
        if tcsetattr(fileHandle.fileDescriptor, TCSAFLUSH, &originalTermios) < 0 {
            throw CallFailure(call: .tcsetattr, errno: errno)
        }
    }
}

@MainActor
public final class RawKeyReader {
    private let fileHandle: FileHandle

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    public func readKeys(
        to callback: @escaping @Sendable (KeyInput) -> Void
    ) -> Task<Void, Never> {
        KeyReader.readKeys(fileHandle: self.fileHandle, to: callback)
    }

    public func keyStream() -> AsyncStream<KeyInput> {
        KeyReader.keyStream(fileHandle: self.fileHandle)
    }
}

private func consumeStart(array: inout [UInt8], bytes: Int) {
    if bytes > 0 && bytes < array.count {
        array.withUnsafeMutableBufferPointer { buffer in
            let src = buffer.baseAddress! + bytes
            let dst = buffer.baseAddress!
            let count = buffer.count - bytes

            // Move remaining bytes to the front
            dst.moveInitialize(from: src, count: count)

            // Zero out the end
            (dst + count).initialize(repeating: 0, count: bytes)
        }
    }
}

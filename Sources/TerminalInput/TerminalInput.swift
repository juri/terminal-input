import Foundation
import Synchronization

@MainActor
public enum KeyReader {
    public static func readKeys(
        fileHandle: FileHandle,
        to callback: @escaping @Sendable (KeyCommand) -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            var buffer = [UInt8](repeating: 0, count: 4)
            var bufferPoint = 0
            loop: while !Task.isCancelled {
                let key: KeyCommand?
                if bufferPoint < 4 {
                    var inputBuffer = [UInt8](repeating: 0, count: 4 - bufferPoint)
                    let bytesRead = read(fileHandle.fileDescriptor, &inputBuffer, 4 - bufferPoint)
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
                    switch buffer[0] {
                    case 0x00: key = .null
                    case 0x01: key = .moveToStart
                    case 0x03: key = .terminate
                    case 0x04: key = .delete
                    case 0x05: key = .moveToEnd
                    case 0x09: key = .tab
                    case 0x0B: key = .deleteToEnd
                    case 0x0D: key = .return
                    case 0x14: key = .transpose
                    case 0x15: key = .deleteToStart
                    case 0x1A: key = .suspend
                    case 0x1B: key = .esc
                    case 0x1C: key = .fileSeparator
                    case 0x1D: key = .groupSeparator
                    case 0x1E: key = .recordSeparator
                    case 0x1F: key = .unitSeparator
                    case 0x7F: key = .backspace
                    default: key = .character(Character(.init(buffer[0])))
                    }
                    consumeStart(array: &buffer, bytes: 1)
                    bufferPoint -= 1
                } else if bufferPoint == 3 {
                    switch (buffer[0], buffer[1], buffer[2]) {
                    case (0x1B, 0x5B, 0x41): key = .up
                    case (0x1B, 0x5B, 0x42): key = .down
                    case (0x1B, 0x5B, 0x43): key = .right
                    case (0x1B, 0x5B, 0x44): key = .left
                    case (0x1B, 0x5B, 0x5A): key = .backtab
                    default: continue loop
                    }
                    consumeStart(array: &buffer, bytes: 3)
                    bufferPoint -= 3
                } else if var str = String(bytes: buffer[0..<bufferPoint], encoding: .utf8),
                    str.count > 0
                {
                    let first = str.removeFirst()
                    let count = first.utf8.count
                    consumeStart(array: &buffer, bytes: count)
                    bufferPoint -= count
                    key = .character(first)
                } else if bufferPoint == 4 {
                    // buffer is already full, and we apparently didn't know what to do with it.
                    buffer[0] = 0
                    buffer[1] = 0
                    buffer[2] = 0
                    buffer[3] = 0
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
    ) -> AsyncStream<KeyCommand> {
        let (stream, continuation) = AsyncStream<KeyCommand>.makeStream()

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
        to callback: @escaping @Sendable (KeyCommand) -> Void
    ) -> Task<Void, Never> {
        KeyReader.readKeys(fileHandle: self.fileHandle, to: callback)
    }

    public func keyStream() -> AsyncStream<KeyCommand> {
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

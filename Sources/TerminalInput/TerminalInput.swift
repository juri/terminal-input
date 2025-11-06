import Foundation
import Synchronization

/// `KeyReader` contains functions for reading keys and managing terminal raw mode.
@MainActor
public enum KeyReader {
    /// Read ``KeyInput`` values from the terminal represented by `fileHandle` and send them to  `callback`
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
                } else if bufferPoint == 2 && buffer[0] == 0x1B,
                    let str = String(bytes: buffer[0..<bufferPoint], encoding: .utf8)
                {
                    key = .escapeSequence(str)
                    consumeStart(array: &buffer, bytes: 2)
                    bufferPoint -= 2
                } else if bufferPoint == 3 {
                    var _key: KeyInput? = nil
                    switch (buffer[0], buffer[1], buffer[2]) {
                    case (0x1B, 0x5B, 0x41): _key = .up
                    case (0x1B, 0x5B, 0x42): _key = .down
                    case (0x1B, 0x5B, 0x43): _key = .right
                    case (0x1B, 0x5B, 0x44): _key = .left
                    case (0x1B, 0x5B, 0x5A): _key = .backtab
                    case let (0x1B, p1, p2):
                        if let str = String(bytes: [p1, p2], encoding: .utf8) {
                            _key = .escapeSequence(str)
                        }
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
                } else if bufferPoint > 2 && buffer[0] == 0x1B && bufferPoint < bufferSize,
                    let str = String(bytes: buffer[0..<bufferPoint], encoding: .utf8)
                {
                    key = .escapeSequence(str)
                    consumeStart(array: &buffer, bytes: bufferPoint)
                    bufferPoint = 0
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
                    for i in 0..<bufferSize {
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

    /// Create an `AsyncStream` of ``KeyInput`` values read from `fileHandle`.
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

    /// An error that represents a failure in a C standard library function.
    public struct CallFailure: Error {
        public let call: Call
        public let errno: Int32

        /// The failed call.
        public enum Call: Sendable {
            case tcgetattr
            case tcsetattr
        }
    }

    /// Run `closure` with the terminal represented by `fileHandle` set in raw mode.
    public static func inRawMode<T>(
        fileHandle: FileHandle,
        closure: (RawKeyReader) async -> T
    ) async throws(CallFailure) -> T {
        let originalTermios = try self.setRaw(fileHandle: fileHandle)
        let rawReader = RawKeyReader(fileHandle: fileHandle)
        let value = await closure(rawReader)
        try self.unsetRaw(fileHandle: fileHandle, originalTermios: originalTermios)
        return value
    }

    /// `FailureInRawMode` represents an error that occured either in raw mode management or
    /// inside the closure executed by ``inRawModeThrowing(fileHandle:closure:)``.
    public enum FailureInRawMode<E: Error>: Error {
        case callFailure(CallFailure)
        case other(E)
    }

    /// Run the throwing `closure` with the terminal represented by `fileHandle` set in raw mode.
    public static func inRawModeThrowing<T, E>(
        fileHandle: FileHandle,
        closure: (RawKeyReader) async throws(E) -> T
    ) async throws(FailureInRawMode<E>) -> T {
        let originalTermios: termios
        do {
            originalTermios = try self.setRaw(fileHandle: fileHandle)
        } catch {
            throw .callFailure(error)
        }
        let rawReader = RawKeyReader(fileHandle: fileHandle)
        let value: T
        do {
            value = try await closure(rawReader)
        } catch {
            throw .other(error)
        }
        do {
            try self.unsetRaw(fileHandle: fileHandle, originalTermios: originalTermios)
        } catch {
            throw .callFailure(error)
        }
        return value
    }

    /// Set the terminal represented by `fileHandle` into raw mode.
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

    /// Unset raw mode in the terminal represented by `fileHandle`.
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

/// `RawKeyReader` is wraps a file handle and allows you to read keys more succintly that ``KeyReader``.
@MainActor
public final class RawKeyReader {
    private let fileHandle: FileHandle

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    /// Read ``KeyInput`` values from the wrapped terminal and send them to `callback`.
    public func readKeys(
        to callback: @escaping @Sendable (KeyInput) -> Void
    ) -> Task<Void, Never> {
        KeyReader.readKeys(fileHandle: self.fileHandle, to: callback)
    }

    /// Create an `AsyncStream` of ``KeyInput`` values read from the wrapped file handle.
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

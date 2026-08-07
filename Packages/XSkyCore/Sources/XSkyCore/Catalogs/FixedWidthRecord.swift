import Foundation

/// A view over one fixed-width ASCII catalog record. Field offsets from
/// the legacy headers are byte offsets; records are parsed as bytes and
/// never indexed through a Unicode `String`. Short records yield blank
/// fields, matching the legacy GET_FIELD macro.
public struct FixedWidthRecord: Sendable {
    public let bytes: ArraySlice<UInt8>

    public init(bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
    }

    /// The raw field bytes at [start, start+length), blank-padded when the
    /// record is short (legacy GET_FIELD).
    public func fieldBytes(at start: Int, length: Int) -> [UInt8] {
        let base = bytes.startIndex
        var out = [UInt8]()
        out.reserveCapacity(length)
        for i in 0..<length {
            let idx = base + start + i
            if idx < bytes.endIndex {
                let b = bytes[idx]
                out.append(b == UInt8(ascii: "\n") ? UInt8(ascii: " ") : b)
            } else {
                out.append(UInt8(ascii: " "))
            }
        }
        return out
    }

    public func field(at start: Int, length: Int) -> String {
        String(decoding: fieldBytes(at: start, length: length), as: UTF8.self)
    }

    public func trimmedField(at start: Int, length: Int) -> String {
        field(at: start, length: length)
            .trimmingCharacters(in: .whitespaces)
    }

    public func isBlank(at start: Int, length: Int) -> Bool {
        fieldBytes(at: start, length: length)
            .allSatisfy { $0 == UInt8(ascii: " ") }
    }

    public func byte(at offset: Int) -> UInt8 {
        let idx = bytes.startIndex + offset
        guard idx < bytes.endIndex else { return UInt8(ascii: " ") }
        return bytes[idx]
    }

    /// C `atoi` semantics: skip leading whitespace, optional sign, digits;
    /// zero for anything else.
    public func intValue(at start: Int, length: Int) -> Int {
        Self.atoi(fieldBytes(at: start, length: length))
    }

    /// C `atof` semantics, sufficient for catalog magnitude fields.
    public func doubleValue(at start: Int, length: Int) -> Double {
        Self.atof(fieldBytes(at: start, length: length))
    }

    public static func atoi(_ field: [UInt8]) -> Int {
        var i = 0
        while i < field.count, field[i] == UInt8(ascii: " ") || field[i] == UInt8(ascii: "\t") {
            i += 1
        }
        var sign = 1
        if i < field.count, field[i] == UInt8(ascii: "-") {
            sign = -1
            i += 1
        } else if i < field.count, field[i] == UInt8(ascii: "+") {
            i += 1
        }
        var value = 0
        while i < field.count, field[i].isASCIIDigit {
            value = value * 10 + Int(field[i] - UInt8(ascii: "0"))
            i += 1
        }
        return sign * value
    }

    public static func atof(_ field: [UInt8]) -> Double {
        var i = 0
        while i < field.count, field[i] == UInt8(ascii: " ") || field[i] == UInt8(ascii: "\t") {
            i += 1
        }
        var sign = 1.0
        if i < field.count, field[i] == UInt8(ascii: "-") {
            sign = -1
            i += 1
        } else if i < field.count, field[i] == UInt8(ascii: "+") {
            i += 1
        }
        var value = 0.0
        while i < field.count, field[i].isASCIIDigit {
            value = value * 10 + Double(field[i] - UInt8(ascii: "0"))
            i += 1
        }
        if i < field.count, field[i] == UInt8(ascii: ".") {
            i += 1
            var scale = 0.1
            while i < field.count, field[i].isASCIIDigit {
                value += Double(field[i] - UInt8(ascii: "0")) * scale
                scale /= 10
                i += 1
            }
        }
        return sign * value
    }
}

/// Splits catalog file data into newline-terminated records without
/// copying, tolerating a missing final newline and CRLF endings.
public enum RecordSplitter {
    public struct Record: Sendable {
        public let record: FixedWidthRecord
        /// Byte range in the original data, excluding the newline.
        public let byteRange: Range<Int>
        public let lineNumber: Int
    }

    public static func records(in data: Data) -> [Record] {
        let bytes = [UInt8](data)
        var result: [Record] = []
        var start = 0
        var line = 0
        var i = 0
        while i <= bytes.count {
            if i == bytes.count || bytes[i] == UInt8(ascii: "\n") {
                if i > start || i < bytes.count {
                    var end = i
                    if end > start, bytes[end - 1] == UInt8(ascii: "\r") {
                        end -= 1
                    }
                    line += 1
                    result.append(
                        Record(
                            record: FixedWidthRecord(bytes: bytes[start..<end]),
                            byteRange: start..<end,
                            lineNumber: line))
                }
                start = i + 1
            }
            i += 1
        }
        // drop a trailing zero-length phantom record from a final newline
        if let last = result.last, last.byteRange.isEmpty {
            result.removeLast()
        }
        return result
    }
}

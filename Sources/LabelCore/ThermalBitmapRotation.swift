/// Rotates packed 1-bit thermal data by 180 degrees without resampling.
/// Each row is byte-aligned, and bit 7 is the leftmost pixel of a byte.
public enum ThermalBitmapRotation {
    public enum RotationError: Error { case invalidDimensions }

    public static func rotated180(_ bytes: [UInt8], bytesPerRow: Int, rows: Int) throws -> [UInt8] {
        guard bytesPerRow > 0, rows > 0, bytes.count == bytesPerRow * rows else {
            throw RotationError.invalidDimensions
        }
        var result = [UInt8](repeating: 0, count: bytes.count)
        for row in 0..<rows {
            for byte in 0..<bytesPerRow {
                let source = bytes[(rows - 1 - row) * bytesPerRow + bytesPerRow - 1 - byte]
                var value = source
                value = (value >> 4) | (value << 4)
                value = ((value & 0xCC) >> 2) | ((value & 0x33) << 2)
                value = ((value & 0xAA) >> 1) | ((value & 0x55) << 1)
                result[row * bytesPerRow + byte] = value
            }
        }
        return result
    }
}

import PocketPrinter5890Kit

extension MonochromeBitmap {
    /// Keeps the exact printer dimensions and 1-bit packing.
    func rotated180() throws -> MonochromeBitmap {
        try MonochromeBitmap(
            width: width,
            height: height,
            bytes: ThermalBitmapRotation.rotated180(bytes, bytesPerRow: widthBytes, rows: height)
        )
    }
}

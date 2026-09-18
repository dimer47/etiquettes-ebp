import Foundation

/// The exact product and print settings used for one submitted print job.
public struct PrintedLabel: Codable, Equatable, Identifiable {
    public let id: UUID
    public let printedAt: Date
    public let label: ProductLabel
    public let size: LabelSize
    public let arrangement: LabelArrangement
    public let densityValue: UInt8
    public let leadingFeedDots: Int
    public let trailingFeedDots: Int
    public let rotateContent180: Bool

    public init(id: UUID = UUID(), printedAt: Date = Date(), label: ProductLabel,
                size: LabelSize, arrangement: LabelArrangement, densityValue: UInt8,
                leadingFeedDots: Int, trailingFeedDots: Int, rotateContent180: Bool) {
        self.id = id
        self.printedAt = printedAt
        self.label = label
        self.size = size
        self.arrangement = arrangement
        self.densityValue = densityValue
        self.leadingFeedDots = leadingFeedDots
        self.trailingFeedDots = trailingFeedDots
        self.rotateContent180 = rotateContent180
    }
}

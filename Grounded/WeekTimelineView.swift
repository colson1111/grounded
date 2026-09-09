import SwiftUI

struct WeekTimelineView: View {
    struct ProfileLayer: Identifiable {
        let id = UUID()
        var color: Color
        var blocks: [ScheduleBlock]
    }

    var layers: [ProfileLayer]
    /// Called when user taps empty space. Args: weekday (Calendar convention 1=Sun…7=Sat), minute of day.
    var onTapEmpty: ((Int, Int) -> Void)?
    /// Called when user taps an existing block.
    var onTapBlock: ((ScheduleBlock) -> Void)?

    private struct DayRow: Identifiable {
        let id: Int  // Calendar weekday
        let label: String
    }

    // Calendar weekday order: 2=Mon … 7=Sat, 1=Sun
    private let rows: [DayRow] = [
        .init(id: 2, label: "Mon"), .init(id: 3, label: "Tue"),
        .init(id: 4, label: "Wed"), .init(id: 5, label: "Thu"),
        .init(id: 6, label: "Fri"), .init(id: 7, label: "Sat"),
        .init(id: 1, label: "Sun")
    ]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.label)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    DayBar(
                        weekday: row.id,
                        layers: layers,
                        onTapEmpty: onTapEmpty.map { cb in { min in cb(row.id, min) } },
                        onTapBlock: onTapBlock
                    )
                }
            }
        }
    }
}

private struct DayBar: View {
    var weekday: Int
    var layers: [WeekTimelineView.ProfileLayer]
    var onTapEmpty: ((Int) -> Void)?
    var onTapBlock: ((ScheduleBlock) -> Void)?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 28)

                ForEach([6, 12, 18], id: \.self) { hour in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 28)
                        .offset(x: CGFloat(hour) / 24.0 * geo.size.width)
                }

                ForEach(layers) { layer in
                    ForEach(layer.blocks.filter { $0.weekdays.contains(weekday) }) { block in
                        let x = CGFloat(block.startMinuteOfDay) / 1440.0 * geo.size.width
                        let w = max(
                            CGFloat(block.endMinuteOfDay - block.startMinuteOfDay) / 1440.0 * geo.size.width,
                            4
                        )
                        RoundedRectangle(cornerRadius: 3)
                            .fill(block.isEnabled ? layer.color.opacity(0.75) : Color.gray.opacity(0.3))
                            .frame(width: w, height: 22)
                            .offset(x: x, y: 3)
                            .onTapGesture { onTapBlock?(block) }
                    }
                }

                if onTapEmpty != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(height: 28)
                        .onTapGesture { location in
                            let minute = Int(location.x / geo.size.width * 1440)
                            onTapEmpty?(min(max(minute, 0), 1380))
                        }
                }
            }
        }
        .frame(height: 28)
    }
}

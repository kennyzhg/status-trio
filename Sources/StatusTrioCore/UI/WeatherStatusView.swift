import SwiftUI

/// The status panel's Weather section: a header row, three day columns and a
/// small high/low temperature trend drawn under them.
struct WeatherStatusView: View {
    let state: WeatherPanelState
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !state.days.isEmpty {
                dayColumns
                if let bounds = state.temperatureBounds, state.days.count > 1 {
                    WeatherTrendView(days: state.days, bounds: bounds)
                        .frame(height: 34)
                        .accessibilityElement()
                        .accessibilityLabel(state.trendLabel)
                        .accessibilityValue(trendSummary)
                }
            }
            if let message = state.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: PanelSummaryActionMetrics.iconGap) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(state.subtitle.isEmpty ? " " : state.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            Button(action: onRefresh) {
                Group {
                    if state.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        PanelActionGlyph(systemName: "arrow.clockwise")
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.isLoading)
            .help(state.refreshLabel)
            .accessibilityLabel(state.refreshLabel)
        }
    }

    private var dayColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(state.days) { day in
                VStack(spacing: 3) {
                    Text(day.label)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: day.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 18))
                        .frame(height: 22)
                        .accessibilityHidden(true)
                    Text(day.text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(verbatim: "\(day.high)° / \(day.low)°")
                        .font(.caption.monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.label)
                .accessibilityValue("\(day.text), \(day.high)° / \(day.low)°")
            }
        }
    }

    private var trendSummary: String {
        state.days.map { "\($0.label) \($0.high)° / \($0.low)°" }.joined(separator: ", ")
    }
}

/// Two polylines, highs over lows, one point per day column centre.
private struct WeatherTrendView: View {
    let days: [WeatherPanelState.Day]
    let bounds: ClosedRange<Int>

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                line(\.high, in: size).stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                line(\.low, in: size).stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    dot(at: point(index: index, value: day.high, in: size), color: .orange)
                    dot(at: point(index: index, value: day.low, in: size), color: .blue)
                }
            }
        }
    }

    private func line(_ value: KeyPath<WeatherPanelState.Day, Int>, in size: CGSize) -> Path {
        Path { path in
            for (index, day) in days.enumerated() {
                let next = point(index: index, value: day[keyPath: value], in: size)
                if index == 0 { path.move(to: next) } else { path.addLine(to: next) }
            }
        }
    }

    private func dot(at point: CGPoint, color: Color) -> some View {
        Circle().fill(color).frame(width: 4, height: 4).position(point)
    }

    /// Columns are equal width, so day `i` sits at the centre of column `i`.
    private func point(index: Int, value: Int, in size: CGSize) -> CGPoint {
        let columnWidth = size.width / CGFloat(max(days.count, 1))
        let x = columnWidth * (CGFloat(index) + 0.5)
        let span = CGFloat(max(bounds.upperBound - bounds.lowerBound, 1))
        let inset: CGFloat = 4
        let fraction = CGFloat(value - bounds.lowerBound) / span
        let y = inset + (1 - fraction) * (size.height - inset * 2)
        return CGPoint(x: x, y: y)
    }
}

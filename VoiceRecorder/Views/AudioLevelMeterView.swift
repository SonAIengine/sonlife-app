import SwiftUI

struct AudioLevelMeterView: View {
    let level: Float // -160 to 0 dB

    private var normalizedLevel: Double {
        Double(max(0, min(1, (level + 60) / 60)))
    }

    private var barColor: Color {
        if level > -20 { return .red }
        if level > -35 { return .green }
        return .gray
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemFill))
                RoundedRectangle(cornerRadius: 6)
                    .fill(barColor)
                    .frame(width: geo.size.width * normalizedLevel)
                    .animation(.linear(duration: 0.1), value: normalizedLevel)
            }
        }
        .frame(height: 14)
    }
}

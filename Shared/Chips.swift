import SwiftUI

/// 칸 안의 한 줄 (공휴일, 일정)
struct ChipItem: Identifiable {
    let id: String
    let title: String
    let color: Color
    let filled: Bool
}

struct ChipView: View {
    let chip: ChipItem
    var onLight: Bool = false
    var fontSize: CGFloat = 9.5

    var body: some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(chip.color).frame(width: 2.5)
            Text(chip.title)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(onLight ? Color.black.opacity(0.85) : Color.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: fontSize + 3.5)
        .background(chip.filled ? chip.color.opacity(onLight ? 0.35 : 0.28) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

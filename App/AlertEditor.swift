import SwiftUI

/// 알림 시점 고르기 (기본 선택지 + 분 단위 직접 설정)
struct AlertEditor: View {
    @Binding var offset: Int?
    let allDay: Bool

    @Environment(\.dismiss) private var dismiss

    // 시간 일정 직접 설정
    @State private var amount: Int = 10
    @State private var unit: Int = 0          // 0 분, 1 시간, 2 일, 3 주
    // 할 일 직접 설정
    @State private var daysBefore: Int = 0
    @State private var time: Date = Calendar.kr.startOfDay(for: Date()).addingTimeInterval(9 * 3600)

    private let unitNames = ["분", "시간", "일", "주"]
    private let unitMinutes = [1, 60, 1440, 10080]

    private var presets: [Int] { allDay ? AlertText.allDayPresets : AlertText.timedPresets }

    private var customOffset: Int {
        if allDay {
            let comps = Calendar.kr.dateComponents([.hour, .minute], from: time)
            let minuteOfDay = (comps.hour ?? 9) * 60 + (comps.minute ?? 0)
            return daysBefore * 1440 - minuteOfDay
        }
        return amount * unitMinutes[unit]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("알림")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                VStack(spacing: 0) {
                    optionRow("알림 없음", selected: offset == nil) { offset = nil }
                    if let off = offset, !presets.contains(off) {
                        divider
                        optionRow("직접 설정: " + AlertText.label(off, allDay: allDay), selected: true) {}
                    }
                    ForEach(presets, id: \.self) { p in
                        divider
                        optionRow(AlertText.label(p, allDay: allDay), selected: offset == p) { offset = p }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                Text("직접 설정")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    if allDay { allDayCustom } else { timedCustom }

                    Text(AlertText.label(customOffset, allDay: allDay))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)

                    Button {
                        offset = customOffset
                    } label: {
                        Text("이 시간으로 알림 설정")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("완료") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .onAppear(perform: loadCustom)
    }

    private var timedCustom: some View {
        HStack(spacing: 0) {
            Picker("", selection: $amount) {
                ForEach(0...300, id: \.self) { n in
                    Text(verbatim: "\(n)").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker("", selection: $unit) {
                ForEach(0..<unitNames.count, id: \.self) { i in
                    Text(unitNames[i]).tag(i)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Text("전")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40)
        }
        .frame(height: 160)
    }

    private var allDayCustom: some View {
        HStack(spacing: 0) {
            Picker("", selection: $daysBefore) {
                ForEach(0...60, id: \.self) { n in
                    Text(n == 0 ? "당일" : (n == 1 ? "전날" : "\(n)일 전")).tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            WheelDatePicker(date: $time, mode: .time, minuteInterval: 1)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 170)
    }

    private func loadCustom() {
        guard let off = offset else { return }
        if allDay {
            let t = -off
            let dayDelta = Int((Double(t) / 1440.0).rounded(.down))
            let minuteOfDay = t - dayDelta * 1440
            daysBefore = max(0, min(60, -dayDelta))
            time = Calendar.kr.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minuteOfDay * 60))
        } else if off > 0 {
            for i in stride(from: unitMinutes.count - 1, through: 0, by: -1) where off % unitMinutes[i] == 0 {
                let n = off / unitMinutes[i]
                if n <= 300 {
                    amount = n
                    unit = i
                    return
                }
            }
            amount = min(300, off)
            unit = 0
        } else {
            amount = 0
            unit = 0
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 16)
    }

    private func optionRow(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

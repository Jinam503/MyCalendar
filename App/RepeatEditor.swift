import SwiftUI

struct RepeatEditor: View {
    @Binding var rule: RepeatRule?
    let start: Date

    @Environment(\.dismiss) private var dismiss
    @State private var showUntilPicker = false

    private let cal = Calendar.kr
    private var startWeekday: Int { cal.component(.weekday, from: start) }
    private var startDay: Int { cal.component(.day, from: start) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("반복")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 4)

                optionRow("반복되지 않음", selected: rule == nil) {
                    rule = nil
                }

                VStack(spacing: 18) {
                    frequencySegment
                    if let r = rule {
                        intervalStepper(r)
                    }
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                if let r = rule {
                    switch r.frequency {
                    case .weekly:
                        weekdayList(r)
                    case .monthly:
                        monthlySection(r)
                    case .daily, .yearly:
                        EmptyView()
                    }
                    untilSection(r)
                }

                Text(RepeatText.summary(rule, start: start))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 4)
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
    }

    // MARK: 일 · 주 · 월 · 년

    private var frequencySegment: some View {
        HStack(spacing: 4) {
            ForEach(RepeatFrequency.allCases) { f in
                let on = rule?.frequency == f
                Button {
                    select(f)
                } label: {
                    Text(f.shortLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(on ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(on ? Color.white : Theme.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func select(_ f: RepeatFrequency) {
        if rule == nil {
            rule = RepeatRule(frequency: f)
        } else {
            rule?.frequency = f
        }
        if f == .weekly, rule?.weekdays.isEmpty == true {
            rule?.weekdays = [startWeekday]
        }
        if f == .monthly, rule?.monthly == MonthlyRule.days([]) {
            rule?.monthly = .days([startDay])
        }
    }

    private func intervalStepper(_ r: RepeatRule) -> some View {
        HStack(spacing: 0) {
            squareButton("minus") {
                rule?.interval = max(1, r.interval - 1)
            }
            .opacity(r.interval <= 1 ? 0.3 : 1)

            Text(r.frequency.intervalText(max(1, r.interval)))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            squareButton("plus") {
                rule?.interval = min(99, r.interval + 1)
            }
        }
    }

    // MARK: 매주

    private func weekdayList(_ r: RepeatRule) -> some View {
        let chosen = r.weekdays.isEmpty ? [startWeekday] : r.weekdays
        return VStack(spacing: 6) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { w in
                optionRow(KFmt.weekdayName(w) + "요일", selected: chosen.contains(w)) {
                    var set = Set(chosen)
                    if set.contains(w) {
                        if set.count > 1 { set.remove(w) }
                    } else {
                        set.insert(w)
                    }
                    rule?.weekdays = set.sorted { RepeatText.order($0) < RepeatText.order($1) }
                }
            }
        }
    }

    // MARK: 매월

    private func monthlySection(_ r: RepeatRule) -> some View {
        let fallbackDay = startDay
        let chosenDays: Set<Int> = {
            if case .days(let l) = r.monthly {
                return Set(l.isEmpty ? [fallbackDay] : l)
            }
            return []
        }()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let wdName = KFmt.weekdayName(startWeekday)

        return VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(1...31, id: \.self) { d in
                    let on = chosenDays.contains(d)
                    Button {
                        var set = chosenDays
                        if set.contains(d) {
                            if set.count > 1 { set.remove(d) }
                        } else {
                            set.insert(d)
                        }
                        rule?.monthly = .days(set.sorted())
                    } label: {
                        Text(verbatim: "\(d)")
                            .font(.system(size: 16, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.black : Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(on ? Color.white : Color.clear, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

            VStack(spacing: 6) {
                optionRow("매월 마지막 날", selected: r.monthly == .lastDay) {
                    rule?.monthly = .lastDay
                }
                ForEach(1...5, id: \.self) { n in
                    optionRow("매월 \(n)번째 \(wdName)요일",
                              selected: r.monthly == .nthWeekday(ordinal: n, weekday: startWeekday)) {
                        rule?.monthly = .nthWeekday(ordinal: n, weekday: startWeekday)
                    }
                }
                optionRow("매월 마지막 \(wdName)요일",
                          selected: r.monthly == .nthWeekday(ordinal: -1, weekday: startWeekday)) {
                    rule?.monthly = .nthWeekday(ordinal: -1, weekday: startWeekday)
                }
            }
        }
    }

    // MARK: 반복 종료

    private func untilSection(_ r: RepeatRule) -> some View {
        let hasUntil = Binding<Bool>(
            get: { rule?.until != nil },
            set: { on in
                rule?.until = on ? (cal.date(byAdding: .month, value: 1, to: start) ?? start) : nil
                if !on { showUntilPicker = false }
            }
        )
        let untilDate = Binding<Date>(
            get: { rule?.until ?? start },
            set: { rule?.until = $0 }
        )

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("반복 종료")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                Spacer()
                if let u = r.until {
                    Button {
                        withAnimation { showUntilPicker.toggle() }
                    } label: {
                        Text(KFmt.dotDate(u))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(showUntilPicker ? Theme.accent : Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.surface2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                SquareSwitch(isOn: hasUntil)
            }
            .padding(14)

            if showUntilPicker && r.until != nil {
                DatePicker("", selection: untilDate, in: cal.startOfDay(for: start)..., displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: 공통

    private func optionRow(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func squareButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.surface2, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

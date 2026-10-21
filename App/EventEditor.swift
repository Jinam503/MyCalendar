import SwiftUI
import PhotosUI
import EventKit

private enum PickTarget { case start, end }

private struct ImageRef: Identifiable {
    let id: String
}

/// 저장할 캘린더 선택지
private struct CalendarChoice: Identifiable {
    let id: String          // "local" 또는 calendarIdentifier
    let calendarID: String? // nil = 내 캘린더
    let title: String
    let color: Color
}

struct EventEditor: View {
    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let original: CalendarEvent?
    private let occurrenceDate: Date

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date
    @State private var colorIndex: Int
    @State private var notes: String
    @State private var location: String
    @State private var url: String
    @State private var imageNames: [String]
    @State private var alertOffset: Int?
    @State private var repeatRule: RepeatRule?
    @State private var calendarID: String?
    /// 할 일로 바꿨을 때 원래 시간을 기억해 뒀다가 되돌릴 때 사용
    @State private var savedTimedStart: Date?
    @State private var savedTimedEnd: Date?

    @State private var picking: PickTarget?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var addedImages: [String] = []
    @State private var showRepeat = false
    @State private var showAlert = false
    @State private var confirmDelete = false
    @State private var viewing: ImageRef?
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    private let cal = Calendar.kr

    init(event: CalendarEvent?, date: Date) {
        original = event
        occurrenceDate = date
        let cal = Calendar.kr
        if let e = event {
            _title = State(initialValue: e.title)
            _isAllDay = State(initialValue: e.isAllDay)
            _start = State(initialValue: e.start)
            _hasEnd = State(initialValue: e.end != nil)
            _end = State(initialValue: e.end ?? (e.isAllDay ? e.start : e.start.addingTimeInterval(3600)))
            _colorIndex = State(initialValue: e.colorIndex)
            _notes = State(initialValue: e.notes)
            _location = State(initialValue: e.location)
            _url = State(initialValue: e.url)
            _imageNames = State(initialValue: e.imageNames)
            _alertOffset = State(initialValue: e.alertOffset)
            _repeatRule = State(initialValue: e.repeatRule)
            _calendarID = State(initialValue: e.ekCalendarID)
        } else {
            // 새 일정: 시작·종료 시간이 있는 일정이 기본 (다음 정시부터 1시간)
            let s = EventEditor.defaultStart(on: date, cal: cal)
            _title = State(initialValue: "")
            _isAllDay = State(initialValue: false)
            _start = State(initialValue: s)
            _hasEnd = State(initialValue: true)
            _end = State(initialValue: s.addingTimeInterval(3600))
            _colorIndex = State(initialValue: 0)
            _notes = State(initialValue: "")
            _location = State(initialValue: "")
            _url = State(initialValue: "")
            _imageNames = State(initialValue: [])
            _alertOffset = State(initialValue: AlertText.defaultTimed)
            _repeatRule = State(initialValue: nil)

            var defaultCal: String? = nil
            if let id = CalendarSettings.defaultCalendarID,
               let c = EKBridge.shared.calendar(id: id), c.allowsContentModifications {
                defaultCal = id
            }
            _calendarID = State(initialValue: defaultCal)
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isExternalTarget: Bool { calendarID != nil }

    private var choices: [CalendarChoice] {
        var list = [CalendarChoice(id: "local", calendarID: nil, title: "내 캘린더", color: Theme.accent)]
        for c in EKBridge.shared.writableCalendars() {
            list.append(CalendarChoice(id: c.calendarIdentifier,
                                       calendarID: c.calendarIdentifier,
                                       title: c.title,
                                       color: Color(cgColor: c.cgColor)))
        }
        return list
    }

    private var currentChoice: CalendarChoice {
        let list = choices
        return list.first { $0.calendarID == calendarID } ?? list[0]
    }

    private var titleColor: Color {
        isExternalTarget ? currentChoice.color : EventPalette.color(colorIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleRow
                        if !isExternalTarget { colorRow }
                        timeSection
                        pickerSection
                        divider
                        repeatRow
                        calendarRow
                        alertRow
                        divider
                        locationRow
                        urlRow
                        memoRow
                        imageRow
                        Spacer(minLength: 120)
                    }
                }
                .scrollDismissesKeyboard(.interactively)

                saveButton
                    .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { cancel() }
                        .foregroundStyle(.white)
                }
                if original != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(Theme.holiday)
                    }
                }
            }
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showRepeat) {
                RepeatEditor(rule: $repeatRule, start: start)
            }
            .navigationDestination(isPresented: $showAlert) {
                AlertEditor(offset: $alertOffset, allDay: isAllDay)
            }
            .confirmationDialog("이 일정을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                if let original, original.repeatRule != nil {
                    Button("이 일정만 삭제", role: .destructive) {
                        store.deleteOccurrence(of: original, on: occurrenceDate)
                        dismiss()
                    }
                    Button("모든 반복 일정 삭제", role: .destructive) {
                        store.delete(original)
                        dismiss()
                    }
                } else if let original {
                    Button("삭제", role: .destructive) {
                        store.delete(original)
                        dismiss()
                    }
                }
                Button("취소", role: .cancel) {}
            }
            .alert("저장하지 못했어요", isPresented: Binding(get: { errorMessage != nil },
                                                        set: { if !$0 { errorMessage = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .fullScreenCover(item: $viewing) { ref in
                ImageViewer(name: ref.id)
            }
            .onChange(of: isAllDay) { _, allDay in
                allDayChanged(allDay)
            }
            .onChange(of: hasEnd) { _, on in
                // 종료 시간을 켜면 시작 기준 1시간 뒤가 기본
                if on && !isAllDay {
                    end = start.addingTimeInterval(3600)
                } else if !on && picking == .end {
                    picking = nil
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(items) }
            }
            .onAppear {
                if original == nil { titleFocused = true }
            }
        }
        .tint(.white)
    }

    // MARK: 제목

    private var titleRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(titleColor)
                .frame(width: 5, height: 40)
            TextField("제목", text: $title, prompt: Text("제목").foregroundColor(Color(white: 0.35)))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .focused($titleFocused)
                .submitLabel(.done)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EventPalette.colors.indices, id: \.self) { i in
                    Circle()
                        .fill(EventPalette.colors[i])
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: colorIndex == i ? 2.5 : 0)
                                .padding(-3)
                        )
                        .padding(4)
                        .onTapGesture { colorIndex = i }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 6)
    }

    // MARK: 날짜 · 시간

    private var timeSection: some View {
        row("clock") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 6) {
                    timeBlock(start, target: .start)
                    if hasEnd && !isAllDay {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        timeBlock(end, target: .end)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 62)

                HStack(spacing: 10) {
                    pillChip("할 일", on: isAllDay) { isAllDay.toggle() }
                    Spacer(minLength: 4)
                    // 할 일 모드에서도 줄 높이가 변하지 않게 자리는 유지
                    Group {
                        Text("종료 시간")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                        SquareSwitch(isOn: $hasEnd)
                    }
                    .opacity(isAllDay ? 0 : 1)
                    .allowsHitTesting(!isAllDay)
                }
                .frame(height: 36)
            }
        }
    }

    private func timeBlock(_ d: Date, target: PickTarget) -> some View {
        let active = picking == target
        let dim = picking != nil && !active
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                picking = active ? nil : target
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                if isAllDay {
                    Text(KFmt.monthDay(d))
                        .font(.system(size: 24, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(KFmt.monthDay(d))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(0.85)
                    Text(KFmt.time(d))
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(dim ? Color(white: 0.55) : Color.white)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(height: 62)
            .background(active ? Theme.surface2 : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 돌려서 고르는 선택기 + 빠른 길이 버튼
    @ViewBuilder
    private var pickerSection: some View {
        if let target = picking {
            VStack(spacing: 10) {
                if target == .start {
                    WheelDatePicker(date: startBinding,
                                    mode: isAllDay ? .date : .dateAndTime,
                                    minuteInterval: 5)
                        .frame(height: 200)
                } else {
                    WheelDatePicker(date: $end,
                                    mode: isAllDay ? .date : .dateAndTime,
                                    minuteInterval: 5,
                                    minimumDate: start)
                        .frame(height: 200)
                }

                if hasEnd && !isAllDay {
                    HStack(spacing: 10) {
                        ForEach([30, 60, 120, 180], id: \.self) { m in
                            durationChip(m)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func durationChip(_ minutes: Int) -> some View {
        let on = Int(end.timeIntervalSince(start) / 60) == minutes
        let label: String
        if minutes == 0 { label = "0분" }
        else if minutes < 60 { label = "\(minutes)분" }
        else if minutes % 60 == 0 { label = "\(minutes / 60)시간" }
        else { label = "\(minutes / 60)시간 \(minutes % 60)분" }
        return pillChip(label, on: on, small: true) {
            end = start.addingTimeInterval(TimeInterval(minutes * 60))
        }
    }

    /// 시작을 옮기면 종료도 같은 간격만큼 따라감
    private var startBinding: Binding<Date> {
        Binding(
            get: { start },
            set: { newValue in
                let gap = max(0, end.timeIntervalSince(start))
                start = newValue
                end = newValue.addingTimeInterval(gap)
            }
        )
    }

    private func dayLengthChip(_ days: Int) -> some View {
        let length = (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0) + 1
        return pillChip("\(days)일", on: length == days, small: true) {
            end = cal.date(byAdding: .day, value: days - 1, to: cal.startOfDay(for: start)) ?? start
        }
    }

    // MARK: 반복 · 캘린더 · 알림

    private var repeatRow: some View {
        Button {
            picking = nil
            showRepeat = true
        } label: {
            row("arrow.clockwise") {
                Text(RepeatText.summary(repeatRule, start: start))
                    .font(.system(size: 17))
                    .foregroundStyle(repeatRule == nil ? Theme.secondaryText : Color.white)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var calendarRow: some View {
        row("calendar") {
            Menu {
                ForEach(choices) { c in
                    Button {
                        calendarID = c.calendarID
                    } label: {
                        if c.calendarID == calendarID {
                            Label(c.title, systemImage: "checkmark")
                        } else {
                            Text(c.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(currentChoice.color).frame(width: 9, height: 9)
                    Text(currentChoice.title)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.surface2, in: Capsule())
            }
        }
    }

    private var alertRow: some View {
        row("bell") {
            Button {
                picking = nil
                showAlert = true
            } label: {
                Text(AlertText.label(alertOffset, allDay: isAllDay))
                    .font(.system(size: 16))
                    .foregroundStyle(alertOffset == nil ? Theme.secondaryText : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.surface2, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 위치 · URL · 메모 · 이미지

    private var locationRow: some View {
        row("mappin.and.ellipse") {
            TextField("위치", text: $location, prompt: Text("위치").foregroundColor(Theme.secondaryText))
                .font(.system(size: 17))
                .foregroundStyle(.white)
        }
    }

    private var urlRow: some View {
        row("link") {
            HStack {
                TextField("URL", text: $url, prompt: Text("URL").foregroundColor(Theme.secondaryText))
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let link = validURL {
                    Button {
                        openURL(link)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var validURL: URL? {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let full = t.contains("://") ? t : "https://" + t
        return URL(string: full)
    }

    private var memoRow: some View {
        row("note.text") {
            TextField("메모", text: $notes, prompt: Text("메모").foregroundColor(Theme.secondaryText), axis: .vertical)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .lineLimit(1...10)
        }
    }

    @ViewBuilder
    private var imageRow: some View {
        if isExternalTarget {
            row("photo") {
                Text("구글·아이폰 캘린더 일정에는 이미지를 넣을 수 없어요")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
        } else {
            row("photo") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(imageNames, id: \.self) { name in
                            thumbnail(name)
                        }
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18))
                                Text("이미지")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 72, height: 72)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func thumbnail(_ name: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let ui = UIImage(contentsOfFile: EventRepository.shared.imageURL(name).path) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.surface
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { viewing = ImageRef(id: name) }

            Button {
                imageNames.removeAll { $0 == name }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    // MARK: 공통

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 20).padding(.vertical, 4)
    }

    private func row<Content: View>(_ icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(Color(white: 0.75))
                .frame(width: 28)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private func pillChip(_ text: String, on: Bool, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: small ? 14 : 16, weight: .semibold))
                .foregroundStyle(on ? Color.white : Theme.secondaryText)
                .padding(.horizontal, small ? 12 : 14)
                .padding(.vertical, small ? 6 : 8)
                .background(on ? Theme.surface2 : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(on ? Color.white : Theme.secondaryText.opacity(0.6), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button(action: save) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background(Color(white: 0.88), in: Circle())
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(trimmedTitle.isEmpty)
        .opacity(trimmedTitle.isEmpty ? 0.4 : 1)
    }

    // MARK: 동작

    private func allDayChanged(_ allDay: Bool) {
        picking = nil
        if allDay {
            // 시간 일정 → 할 일: 원래 시간 기억
            savedTimedStart = start
            savedTimedEnd = end
            start = cal.startOfDay(for: start)
            end = start
        } else if let ts = savedTimedStart, let te = savedTimedEnd {
            // 할 일 → 시간 일정: 기억해 둔 시간 그대로 (날짜를 바꿨으면 그 날짜로)
            let shift = cal.dateComponents([.day], from: cal.startOfDay(for: ts), to: cal.startOfDay(for: start)).day ?? 0
            start = cal.date(byAdding: .day, value: shift, to: ts) ?? ts
            end = cal.date(byAdding: .day, value: shift, to: te) ?? te
        } else {
            // 원래 할 일이던 일정: 가까운 다음 정시부터 1시간
            let s = Self.defaultStart(on: start, cal: cal)
            start = s
            end = s.addingTimeInterval(3600)
            hasEnd = true
        }
        if alertOffset != nil {
            alertOffset = AlertText.defaultOffset(allDay: allDay)
        }
    }

    /// 오늘이면 다음 정시, 다른 날이면 오전 9시
    static func defaultStart(on date: Date, cal: Calendar) -> Date {
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        if cal.isDateInToday(date) {
            comps.hour = min(cal.component(.hour, from: Date()) + 1, 23)
        } else {
            comps.hour = 9
        }
        comps.minute = 0
        return cal.date(from: comps) ?? date
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data),
                  let jpg = img.resizedForStorage().jpegData(compressionQuality: 0.8),
                  let name = EventRepository.shared.saveImage(jpg) else { continue }
            imageNames.append(name)
            addedImages.append(name)
        }
        photoItems = []
    }

    private func cancel() {
        EventRepository.shared.deleteImages(addedImages)
        dismiss()
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        var s = start
        var e: Date? = (hasEnd && !isAllDay) ? end : nil
        if isAllDay {
            s = cal.startOfDay(for: start)
        } else if let ee = e, ee < s {
            e = s
        }

        var rule = repeatRule
        if let u = rule?.until, u < s { rule?.until = s }

        var event = CalendarEvent(id: original?.id ?? UUID(),
                                  title: trimmedTitle,
                                  start: s,
                                  end: e,
                                  isAllDay: isAllDay,
                                  colorIndex: colorIndex,
                                  notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                  location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                                  url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                  imageNames: isExternalTarget ? [] : imageNames,
                                  alertOffset: alertOffset,
                                  repeatRule: rule,
                                  exceptions: original?.exceptions ?? [])
        event.ekEventID = original?.ekEventID
        event.ekCalendarID = calendarID
        event.ekOccurrenceStart = original?.ekOccurrenceStart

        do {
            try store.save(event, to: calendarID, original: original)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let kept = isExternalTarget ? [] : imageNames
        let removed = ((original?.imageNames ?? []) + addedImages).filter { !kept.contains($0) }
        EventRepository.shared.deleteImages(removed)

        if alertOffset != nil && !isExternalTarget { NotificationScheduler.requestAuthorization() }
        dismiss()
    }
}

// MARK: - 이미지 크게 보기

private struct ImageViewer: View {
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let ui = UIImage(contentsOfFile: EventRepository.shared.imageURL(name).path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .onTapGesture { dismiss() }
    }
}

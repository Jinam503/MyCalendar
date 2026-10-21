import SwiftUI
import PhotosUI

private enum PickTarget { case start, end }

private struct ImageRef: Identifiable {
    let id: String
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
    @State private var alert: AlertOption
    @State private var repeatRule: RepeatRule?

    @State private var picking: PickTarget?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var addedImages: [String] = []
    @State private var showRepeat = false
    @State private var confirmDelete = false
    @State private var viewing: ImageRef?
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
            _alert = State(initialValue: e.alert)
            _repeatRule = State(initialValue: e.repeatRule)
        } else {
            // 새 일정: 기본은 "할 일"
            let day = cal.startOfDay(for: date)
            _title = State(initialValue: "")
            _isAllDay = State(initialValue: true)
            _start = State(initialValue: day)
            _hasEnd = State(initialValue: false)
            _end = State(initialValue: day)
            _colorIndex = State(initialValue: 0)
            _notes = State(initialValue: "")
            _location = State(initialValue: "")
            _url = State(initialValue: "")
            _imageNames = State(initialValue: [])
            _alert = State(initialValue: AlertOption.defaultFor(allDay: true))
            _repeatRule = State(initialValue: nil)
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var pickerComponents: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleRow
                        colorRow
                        timeSection
                        pickerSection
                        divider
                        repeatRow
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
            .fullScreenCover(item: $viewing) { ref in
                ImageViewer(name: ref.id)
            }
            .onChange(of: isAllDay) { _, allDay in
                allDayChanged(allDay)
            }
            .onChange(of: start) { old, new in
                // 시작을 옮기면 종료도 같은 간격만큼 따라감
                let gap = max(0, end.timeIntervalSince(old))
                end = new.addingTimeInterval(gap)
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
            Rectangle()
                .fill(EventPalette.color(colorIndex))
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
                    Rectangle()
                        .fill(EventPalette.colors[i])
                        .frame(width: 26, height: 26)
                        .overlay(
                            Rectangle().stroke(Color.white, lineWidth: colorIndex == i ? 2 : 0)
                        )
                        .padding(2)
                        .onTapGesture { colorIndex = i }
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 10)
    }

    // MARK: 날짜 · 시간

    private var timeSection: some View {
        row("clock") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    timeBlock(start, target: .start)
                    if hasEnd {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.secondaryText)
                        timeBlock(end, target: .end)
                    }
                    Spacer(minLength: 4)
                    squareChip("할 일", on: isAllDay) { isAllDay.toggle() }
                }
                HStack {
                    Text(isAllDay ? "종료일 지정" : "종료 시간 지정")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    SquareSwitch(isOn: $hasEnd)
                }
            }
        }
    }

    private func timeBlock(_ d: Date, target: PickTarget) -> some View {
        let active = picking == target
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                picking = active ? nil : target
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                if isAllDay {
                    Text(KFmt.monthDay(d))
                        .font(.system(size: 20, weight: .bold))
                } else {
                    Text(KFmt.monthDay(d))
                        .font(.system(size: 13))
                        .opacity(0.85)
                    Text(KFmt.time(d))
                        .font(.system(size: 26, weight: .bold))
                }
            }
            .foregroundStyle(active ? Theme.accent : Color.white)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pickerSection: some View {
        if picking == .start {
            DatePicker("", selection: $start,
                       displayedComponents: pickerComponents)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Theme.accent)
                .padding(.horizontal, 16)
        } else if picking == .end && hasEnd {
            DatePicker("", selection: $end, in: start...,
                       displayedComponents: pickerComponents)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Theme.accent)
                .padding(.horizontal, 16)
        }
    }

    // MARK: 반복 · 알림

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

    private var alertRow: some View {
        row("bell") {
            Menu {
                ForEach(isAllDay ? AlertOption.allDayOptions : AlertOption.timedOptions) { opt in
                    Button {
                        alert = opt
                    } label: {
                        if alert == opt {
                            Label(opt.label, systemImage: "checkmark")
                        } else {
                            Text(opt.label)
                        }
                    }
                }
            } label: {
                Text(alert.label)
                    .font(.system(size: 16))
                    .foregroundStyle(alert == .none ? Theme.secondaryText : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.surface2)
            }
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

    private var imageRow: some View {
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
                        .background(Theme.surface)
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
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { viewing = ImageRef(id: name) }

            Button {
                imageNames.removeAll { $0 == name }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.7))
            }
            .buttonStyle(.plain)
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
        .padding(.vertical, 14)
    }

    private func squareChip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? Color.black : Theme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(on ? Color.white : Color.clear)
                .overlay(Rectangle().stroke(on ? Color.white : Theme.secondaryText, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button(action: save) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background(Color.white)
        }
        .buttonStyle(.plain)
        .disabled(trimmedTitle.isEmpty)
        .opacity(trimmedTitle.isEmpty ? 0.4 : 1)
    }

    // MARK: 동작

    private func allDayChanged(_ allDay: Bool) {
        if allDay {
            start = cal.startOfDay(for: start)
            end = cal.startOfDay(for: end)
        } else if cal.startOfDay(for: start) == start {
            // 할 일 → 시간 일정: 그날의 다음 정시로
            var comps = cal.dateComponents([.year, .month, .day], from: start)
            comps.hour = min(cal.component(.hour, from: Date()) + 1, 23)
            comps.minute = 0
            let s = cal.date(from: comps) ?? start
            start = s
            end = s.addingTimeInterval(3600)
        }
        let options = allDay ? AlertOption.allDayOptions : AlertOption.timedOptions
        if !options.contains(alert) {
            alert = AlertOption.defaultFor(allDay: allDay)
        }
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
        // 저장 안 하고 닫으면 새로 넣은 이미지는 지움
        EventRepository.shared.deleteImages(addedImages)
        dismiss()
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        var s = start
        var e: Date? = hasEnd ? end : nil
        if isAllDay {
            s = cal.startOfDay(for: start)
            if let ee = e {
                let lastDay = cal.startOfDay(for: ee)
                e = lastDay > s ? lastDay : nil
            }
        } else if let ee = e, ee < s {
            e = s
        }

        var rule = repeatRule
        if let u = rule?.until, u < s { rule?.until = s }

        let event = CalendarEvent(id: original?.id ?? UUID(),
                                  title: trimmedTitle,
                                  start: s,
                                  end: e,
                                  isAllDay: isAllDay,
                                  colorIndex: colorIndex,
                                  notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                  location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                                  url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                  imageNames: imageNames,
                                  alert: alert,
                                  repeatRule: rule,
                                  exceptions: original?.exceptions ?? [])
        store.upsert(event)

        // 빼낸 이미지 파일 정리
        let removed = ((original?.imageNames ?? []) + addedImages).filter { !imageNames.contains($0) }
        EventRepository.shared.deleteImages(removed)

        if alert != .none { NotificationScheduler.requestAuthorization() }
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.15))
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .onTapGesture { dismiss() }
    }
}

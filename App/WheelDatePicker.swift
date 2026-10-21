import SwiftUI
import UIKit

/// 돌려서 고르는 날짜·시간 선택기 (5분 단위 등 설정 가능)
struct WheelDatePicker: UIViewRepresentable {
    @Binding var date: Date
    var mode: UIDatePicker.Mode = .dateAndTime
    var minuteInterval: Int = 5
    var minimumDate: Date? = nil

    func makeUIView(context: Context) -> UIDatePicker {
        let p = UIDatePicker()
        p.preferredDatePickerStyle = .wheels
        p.datePickerMode = mode
        p.minuteInterval = minuteInterval
        p.locale = koLocale
        p.calendar = Calendar.kr
        p.overrideUserInterfaceStyle = .dark
        p.date = date
        p.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        p.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return p
    }

    func updateUIView(_ p: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        if p.datePickerMode != mode { p.datePickerMode = mode }
        if p.minuteInterval != minuteInterval { p.minuteInterval = minuteInterval }
        p.minimumDate = minimumDate
        if abs(p.date.timeIntervalSince(date)) > 0.5 {
            p.setDate(date, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: WheelDatePicker
        init(_ parent: WheelDatePicker) { self.parent = parent }

        @objc func changed(_ sender: UIDatePicker) {
            parent.date = sender.date
        }
    }
}

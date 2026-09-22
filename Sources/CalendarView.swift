import SwiftUI

final class CalendarModel: ObservableObject {
    @Published var displayedMonth: Date = Date()
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @Published var eventsByDay: [Date: [CalendarEvent]] = [:]
    @Published var status: String? = nil
    @Published var isLoading = false

    var grid: MonthGrid { MonthGrid.make(for: displayedMonth) }
    var selectedEvents: [CalendarEvent] { eventsByDay[Calendar.current.startOfDay(for: selectedDay)] ?? [] }

    func hasEvents(_ d: Date) -> Bool { !(eventsByDay[Calendar.current.startOfDay(for: d)] ?? []).isEmpty }

    func shiftMonth(_ delta: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
        onMonthChanged?()
    }

    func goToday() {
        displayedMonth = Date()
        selectedDay = Calendar.current.startOfDay(for: Date())
        onMonthChanged?()
    }

    var onMonthChanged: (() -> Void)?
}

struct CalendarView: View {
    @ObservedObject var model: CalendarModel
    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            weekdays
            grid
            Divider()
            dayList
            if let s = model.status {
                Text(s).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340)
        .font(.system(.body, design: .monospaced))
    }

    private var header: some View {
        HStack {
            Button { model.shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
            Spacer()
            Text(Fmt.monthTitle(model.displayedMonth).capitalized).font(.system(.headline, design: .monospaced))
                .onTapGesture { model.goToday() }
            if model.isLoading { ProgressView().controlSize(.small).padding(.leading, 6) }
            Spacer()
            Button { model.shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
        }
    }

    private var weekdays: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Fmt.weekdaySymbols(), id: \.self) { s in
                Text(s.replacingOccurrences(of: ".", with: "")).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(model.grid.cells, id: \.date) { cell in
                dayCell(cell)
            }
        }
    }

    private func dayCell(_ cell: MonthGrid.Cell) -> some View {
        let isSelected = cal.isDate(cell.date, inSameDayAs: model.selectedDay)
        let isToday = cal.isDateInToday(cell.date)
        return VStack(spacing: 2) {
            Text("\(cal.component(.day, from: cell.date))")
                .font(.system(.callout, design: .monospaced).weight(isToday ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.white : (cell.inMonth ? Color.primary : Color.secondary.opacity(0.5)))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.18) : Color.clear))
                )
            Circle().fill(model.hasEvents(cell.date) ? Color.accentColor : Color.clear).frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedDay = cal.startOfDay(for: cell.date) }
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Fmt.dayTitle(model.selectedDay).capitalized).font(.system(.headline, design: .monospaced))
            if model.selectedEvents.isEmpty {
                Text("Aucun événement").foregroundStyle(.secondary).font(.system(.callout, design: .monospaced))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.selectedEvents) { e in eventRow(e) }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private func eventRow(_ e: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(color(e.colorHex)).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(e.isAllDay ? "Journée" : Fmt.time(e.start)).foregroundStyle(.secondary)
                        .font(.system(.callout, design: .monospaced))
                    Text(e.title).font(.system(.callout, design: .monospaced)).lineLimit(1)
                }
                Text([e.calendarName, e.location].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func color(_ hex: String?) -> Color {
        guard let hex = hex, let c = NSColor(hex: hex) else { return .accentColor }
        return Color(nsColor: c)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

import SwiftUI

final class CalendarModel: ObservableObject {
    @Published var displayedMonth: Date = Date()
    /// nil = show upcoming events; a date = show that day's events.
    @Published var selectedDay: Date? = nil
    @Published var events: [CalendarEvent] = [] {
        didSet { eventsByDay = EventIndex.byDay(events) }
    }
    @Published private(set) var eventsByDay: [Date: [CalendarEvent]] = [:]
    @Published var status: String? = nil
    @Published var isLoading = false

    var grid: MonthGrid { MonthGrid.make(for: displayedMonth) }
    var upcoming: [CalendarEvent] { EventIndex.upcoming(events, limit: 5) }
    func dayEvents(_ d: Date) -> [CalendarEvent] { eventsByDay[Calendar.current.startOfDay(for: d)] ?? [] }
    func hasEvents(_ d: Date) -> Bool { !dayEvents(d).isEmpty }

    /// Fetch window: the visible grid, extended so the upcoming list always has a month of runway.
    var fetchRange: (start: Date, end: Date) {
        let g = grid.visibleRange
        let horizon = Calendar.current.date(byAdding: .day, value: 31, to: Date())!
        return (min(g.start, Date()), max(g.end, horizon))
    }

    func select(_ d: Date) {
        let day = Calendar.current.startOfDay(for: d)
        selectedDay = (selectedDay == day) ? nil : day
    }

    func shiftMonth(_ delta: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
        onMonthChanged?()
    }

    func goToday() {
        displayedMonth = Date()
        selectedDay = nil
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
            if let day = model.selectedDay { dayList(day) } else { upcomingList }
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
            ForEach(model.grid.cells, id: \.date) { cell in dayCell(cell) }
        }
    }

    private func dayCell(_ cell: MonthGrid.Cell) -> some View {
        let isSelected = model.selectedDay.map { cal.isDate(cell.date, inSameDayAs: $0) } ?? false
        let isToday = cal.isDateInToday(cell.date)
        return VStack(spacing: 2) {
            Text("\(cal.component(.day, from: cell.date))")
                .font(.system(.callout, design: .monospaced).weight(isToday ? .bold : .regular))
                .foregroundStyle(isSelected || isToday ? Color.white : (cell.inMonth ? Color.primary : Color.secondary.opacity(0.5)))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(isToday ? Color.accentColor : (isSelected ? Color.secondary.opacity(0.35) : Color.clear))
                )
            Circle().fill(model.hasEvents(cell.date) ? Color.accentColor : Color.clear).frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.select(cell.date) }
    }

    // MARK: - Lists

    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("À venir").font(.system(.headline, design: .monospaced))
            let items = model.upcoming
            if items.isEmpty {
                Text("Aucun événement à venir").foregroundStyle(.secondary).font(.system(.callout, design: .monospaced))
            } else {
                ForEach(items) { e in eventRow(e, showDay: true) }
            }
        }
    }

    private func dayList(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Fmt.dayTitle(day).capitalized).font(.system(.headline, design: .monospaced))
                Spacer()
                Button("À venir") { model.selectedDay = nil }.buttonStyle(.borderless)
                    .font(.system(.caption, design: .monospaced))
            }
            let items = model.dayEvents(day)
            if items.isEmpty {
                Text("Aucun événement").foregroundStyle(.secondary).font(.system(.callout, design: .monospaced))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { e in eventRow(e, showDay: false) }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private func eventRow(_ e: CalendarEvent, showDay: Bool) -> some View {
        let when = [showDay ? Fmt.relativeDay(e.start) : nil, e.isAllDay ? "Journée" : Fmt.time(e.start)]
            .compactMap { $0 }.joined(separator: " ")
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(color(e.colorHex)).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(when).foregroundStyle(.secondary).font(.system(.callout, design: .monospaced))
                    Text(e.title).font(.system(.callout, design: .monospaced)).lineLimit(1)
                }
                if let loc = e.location {
                    Text(loc).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
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

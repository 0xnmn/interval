import EventKit
import Foundation
import IntervalCore
import Observation

struct CalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
}

enum CalendarAccessState: Equatable {
    case notDetermined, fullAccess, denied, restricted, error(String)
}

/// Read-only EventKit adapter. Access is requested only by `requestFullAccessToEvents()`.
@MainActor @Observable
final class CalendarService {
    private(set) var authorizationState: CalendarAccessState = .notDetermined
    private(set) var calendars: [CalendarChoice] = []
    private(set) var historyEvents: [CalendarEventSnapshot] = []
    private(set) var todayEvents: [CalendarEventSnapshot] = []
    private(set) var isEnabled = false
    private(set) var selectedCalendarIDs: Set<String> = []

    private let store: EKEventStore?
    private let fixtureEvents: [CalendarEventSnapshot]?
    private var displayedMonth = Date()
    private var todayInterval: DateInterval?
    private var observer: NSObjectProtocol?
    private var timeZoneObserver: NSObjectProtocol?
    private var minuteTask: Task<Void, Never>?

    init(fixtureEvents: [CalendarEventSnapshot]? = nil) {
        self.fixtureEvents = fixtureEvents
        store = fixtureEvents == nil ? EKEventStore() : nil
        if let fixtureEvents {
            authorizationState = .fullAccess
            calendars = Array(Set(fixtureEvents.map(\.calendarName))).sorted().map { CalendarChoice(id: $0, title: $0) }
            historyEvents = fixtureEvents
        }
        updateAuthorizationState()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timeZoneObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange,
                                                                   object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.timeZoneDidChange() }
        }
        minuteTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refreshAuthorizationAndToday()
            }
        }
    }

    /// The sole permission-requesting API. Call only from an explicit user action.
    func requestFullAccessToEvents() async -> Bool {
        guard fixtureEvents == nil, let store else { return authorizationState == .fullAccess }
        do {
            let granted = try await store.requestFullAccessToEvents()
            updateAuthorizationState()
            return granted && authorizationState == .fullAccess
        } catch {
            authorizationState = .error(error.localizedDescription)
            return false
        }
    }

    func configure(enabled: Bool, selectedCalendarIDs: Set<String>) {
        isEnabled = enabled
        self.selectedCalendarIDs = selectedCalendarIDs
        updateAuthorizationState()
        refresh()
    }

    func show(month: Date) {
        displayedMonth = month
        refreshHistory()
    }

    func hasEvent(at date: Date) -> Bool {
        refreshAuthorization()
        guard isEnabled, authorizationState == .fullAccess else { return false }
        if todayInterval == nil || date < todayInterval!.start || date >= todayInterval!.end {
            refreshToday(containing: date)
        }
        return todayEvents.contains { $0.isEligibleForReminderSuppression && $0.start <= date && $0.end > date }
    }

    func events(on day: Date, calendar: Calendar = .autoupdatingCurrent) -> [CalendarEventSnapshot] {
        guard isEnabled, authorizationState == .fullAccess,
              let interval = CalendarDates.dayInterval(containing: day, calendar: calendar) else { return [] }
        return historyEvents.filter { $0.overlaps(interval) }.sorted { $0.start < $1.start }
    }

    /// Re-checks the system on every entry point where stale permission could expose cached data.
    private func refreshAuthorization() {
        guard fixtureEvents == nil else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: authorizationState = .notDetermined
        case .fullAccess: authorizationState = .fullAccess
        case .denied: authorizationState = .denied
        case .restricted: authorizationState = .restricted
        case .writeOnly: authorizationState = .denied
        @unknown default: authorizationState = .restricted
        }
        if authorizationState != .fullAccess {
            historyEvents = []
            todayEvents = []
            todayInterval = nil
        }
        loadCalendars()
    }

    private func updateAuthorizationState() { refreshAuthorization() }

    private func loadCalendars() {
        guard authorizationState == .fullAccess else { calendars = []; return }
        calendars = store?.calendars(for: .event).map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } ?? []
    }

    func applicationDidActivate() { refresh() }

    private func refresh() {
        refreshAuthorization()
        refreshHistory()
        refreshToday(containing: Date())
    }

    private func refreshAuthorizationAndToday() {
        refreshAuthorization()
        refreshToday(containing: Date())
    }

    private func timeZoneDidChange() {
        todayInterval = nil
        refresh()
    }

    private func refreshHistory() {
        guard let interval = CalendarDates.monthInterval(containing: displayedMonth, calendar: .autoupdatingCurrent) else { return }
        query(interval: interval) { [weak self] events in self?.historyEvents = events }
    }

    private func refreshToday(containing date: Date) {
        guard let interval = CalendarDates.dayInterval(containing: date, calendar: .autoupdatingCurrent) else {
            todayEvents = []
            todayInterval = nil
            return
        }
        todayInterval = interval
        query(interval: interval) { [weak self] events in self?.todayEvents = events }
    }

    private func query(interval: DateInterval, completion: @escaping @MainActor ([CalendarEventSnapshot]) -> Void) {
        guard isEnabled, authorizationState == .fullAccess, !selectedCalendarIDs.isEmpty else {
            completion([]); return
        }
        if let fixtureEvents {
            completion(fixtureEvents.filter {
                selectedCalendarIDs.contains($0.calendarName) && $0.overlaps(interval)
            }); return
        }
        guard let store else { completion([]); return }
        let selected = store.calendars(for: .event).filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { completion([]); return }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: selected)
        completion(store.events(matching: predicate).map(Self.snapshot))
    }

    private static func snapshot(_ event: EKEvent) -> CalendarEventSnapshot {
        let status: CalendarEventStatus
        if event.status == .canceled { status = .canceled }
        else if event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined { status = .declined }
        else if event.status == .tentative { status = .tentative }
        else { status = .confirmed }
        return CalendarEventSnapshot(id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "Untitled event",
            start: event.startDate, end: event.endDate, allDay: event.isAllDay,
            calendarName: event.calendar.title, status: status)
    }
}

import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = CalendarModel()
    private let auth = GoogleAuth()
    private lazy var api = GoogleCalendarAPI(auth: auth)
    private var refreshTimer: Timer?
    private var lastRefresh = Date.distantPast
    private var shownDay = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.imagePosition = .imageOnly
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: CalendarView(model: model))
        model.onMonthChanged = { [weak self] in self?.refresh(force: true) }

        installEditMenu()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateIcon()
            if Date().timeIntervalSince(self.lastRefresh) > 5 * 60 { self.refresh(force: true) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh(force: true)
        }
        refresh(force: true)
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
    }

    // MARK: - Status item

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil); return }
        guard let b = statusItem.button else { return }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        refresh(force: false)
    }

    private func updateIcon() {
        let day = Calendar.current.component(.day, from: Date())
        guard day != shownDay else { return }
        shownDay = day
        statusItem.button?.image = StatusIcon.image(day: day)
        if Calendar.current.isDateInToday(model.selectedDay) == false, Calendar.current.isDate(model.selectedDay, inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: Date())!) {
            model.goToday()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let accounts = GoogleAccount.all()
        if accounts.isEmpty {
            menu.addItem(NSMenuItem(title: "Aucun compte Google", action: nil, keyEquivalent: ""))
        }
        for a in accounts {
            let item = NSMenuItem(title: "Retirer \(a.email)", action: #selector(removeAccount(_:)), keyEquivalent: "")
            item.representedObject = a.email
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ajouter un compte Google…", action: #selector(addAccount), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Configurer l'identifiant OAuth…", action: #selector(configureClient), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Actualiser", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    // MARK: - Data

    @objc private func refreshNow() { refresh(force: true) }

    private func refresh(force: Bool) {
        if !force, Date().timeIntervalSince(lastRefresh) < 30 { return }
        guard let client = OAuthClient.load() else { model.status = AuthError.noClient.message; return }
        let accounts = GoogleAccount.all()
        guard !accounts.isEmpty else { model.status = AuthError.noAccount.message; return }
        lastRefresh = Date()
        model.isLoading = true
        let range = model.grid.visibleRange
        api.fetchAll(accounts: accounts, client: client, from: range.start, to: range.end) { [weak self] result in
            guard let self = self else { return }
            self.model.isLoading = false
            self.model.eventsByDay = EventIndex.byDay(result.events)
            self.model.status = result.errors.isEmpty ? nil : result.errors.joined(separator: "\n")
        }
    }

    // MARK: - Accounts

    @objc private func addAccount() {
        guard let client = OAuthClient.load() else { configureClient(); return }
        auth.signIn(client: client) { [weak self] r in
            switch r {
            case .success(let account):
                if !account.save() { self?.alert("Impossible d'enregistrer le compte dans le Trousseau") }
                self?.refresh(force: true)
            case .failure(let e):
                if case .cancelled = e { return }
                self?.alert(e.message)
            }
        }
    }

    @objc private func removeAccount(_ sender: NSMenuItem) {
        guard let email = sender.representedObject as? String else { return }
        GoogleAccount.remove(email: email)
        auth.forget(email: email)
        refresh(force: true)
    }

    @objc private func configureClient() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Identifiant OAuth Google"
        alert.informativeText = "Dans Google Cloud Console : API Google Calendar activée, écran de consentement en Production, identifiant OAuth de type « Application de bureau ». Colle ici l'ID client et le secret. Ils sont stockés dans ton Trousseau."
        let box = NSStackView(frame: NSRect(x: 0, y: 0, width: 420, height: 58))
        box.orientation = .vertical
        box.spacing = 6
        let idField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        idField.placeholderString = "ID client (…apps.googleusercontent.com)"
        let secretField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        secretField.placeholderString = "Secret client"
        if let c = OAuthClient.load() { idField.stringValue = c.id; secretField.stringValue = c.secret }
        box.addArrangedSubview(idField); box.addArrangedSubview(secretField)
        idField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        secretField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        alert.accessoryView = box
        alert.addButton(withTitle: "Enregistrer")
        alert.addButton(withTitle: "Annuler")
        alert.window.initialFirstResponder = idField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let client = OAuthClient(id: idField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                 secret: secretField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !client.id.isEmpty else { return }
        if !client.save() { self.alert("Impossible d'enregistrer dans le Trousseau"); return }
        if GoogleAccount.all().isEmpty { addAccount() } else { refresh(force: true) }
    }

    private func alert(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "Claude Calendar"; a.informativeText = text; a.runModal()
    }

    /// LSUIElement apps have no main menu, so ⌘V/⌘C/⌘A do nothing in dialogs unless we install an Edit menu.
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem(title: "Édition", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Édition")
        edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

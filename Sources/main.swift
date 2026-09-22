import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = CalendarModel()
    private let fetcher = FeedFetcher()
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
        let hosting = NSHostingController(rootView: CalendarView(model: model))
        hosting.sizingOptions = [.preferredContentSize]   // size known before showing, so the popover anchors correctly
        popover.contentViewController = hosting
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
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        refresh(force: false)
    }

    private func updateIcon() {
        let day = Calendar.current.component(.day, from: Date())
        guard day != shownDay else { return }
        shownDay = day
        statusItem.button?.image = StatusIcon.image(day: day)
        model.objectWillChange.send()   // new day: "Aujourd'hui"/"Demain" labels and the upcoming list shift
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let feeds = FeedStore.load()
        if feeds.isEmpty {
            menu.addItem(NSMenuItem(title: "Aucun agenda", action: nil, keyEquivalent: ""))
        }
        for f in feeds {
            let item = NSMenuItem(title: "Retirer « \(f.name.isEmpty ? f.url : f.name) »", action: #selector(removeFeed(_:)), keyEquivalent: "")
            item.representedObject = f.url
            item.target = self
            item.image = swatch(f.colorHex)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ajouter un agenda iCal…", action: #selector(addFeed), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Actualiser", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func swatch(_ hex: String) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { _ in
            (NSColor(hex: hex) ?? .controlAccentColor).setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 10, height: 10)).fill()
            return true
        }
    }

    // MARK: - Data

    @objc private func refreshNow() { refresh(force: true) }

    private func refresh(force: Bool) {
        if !force, Date().timeIntervalSince(lastRefresh) < 30 { return }
        let feeds = FeedStore.load()
        guard !feeds.isEmpty else { model.status = "Aucun agenda : clic droit → Ajouter un agenda iCal…"; return }
        lastRefresh = Date()
        model.isLoading = true
        let range = model.fetchRange
        fetcher.fetch(feeds, from: range.start, to: range.end) { [weak self] result in
            guard let self = self else { return }
            self.model.isLoading = false
            self.model.events = result.events
            self.model.status = result.errors.isEmpty ? nil : result.errors.joined(separator: "\n")
        }
    }

    // MARK: - Feeds

    @objc private func addFeed() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Ajouter un agenda iCal"
        alert.informativeText = "Google Agenda → Paramètres → l'agenda → « Adresse secrète au format iCal ». Colle l'URL ici (⌘V). Elle est stockée dans ton Trousseau."
        let box = NSStackView(frame: NSRect(x: 0, y: 0, width: 440, height: 88))
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 6
        let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 440, height: 24))
        urlField.placeholderString = "https://calendar.google.com/calendar/ical/…/basic.ics"
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 440, height: 24))
        nameField.placeholderString = "Nom (facultatif, sinon celui du flux)"
        let colorPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 24), pullsDown: false)
        for c in FeedColor.allCases {
            colorPopup.addItem(withTitle: c.rawValue)
            colorPopup.lastItem?.image = swatch(c.hex)
        }
        colorPopup.selectItem(at: FeedStore.load().count % FeedColor.allCases.count)
        box.addArrangedSubview(urlField); box.addArrangedSubview(nameField); box.addArrangedSubview(colorPopup)
        urlField.widthAnchor.constraint(equalToConstant: 440).isActive = true
        nameField.widthAnchor.constraint(equalToConstant: 440).isActive = true
        alert.accessoryView = box
        alert.addButton(withTitle: "Ajouter")
        alert.addButton(withTitle: "Annuler")
        alert.window.initialFirstResponder = urlField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var urlString = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlString.hasPrefix("webcal://") { urlString = "https://" + urlString.dropFirst("webcal://".count) }
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else { self.alert("URL invalide"); return }
        let color = FeedColor.allCases[max(colorPopup.indexOfSelectedItem, 0)]
        let feed = Feed(name: nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), url: urlString, colorHex: color.hex)
        guard FeedStore.add(feed) else { self.alert("Impossible d'enregistrer dans le Trousseau"); return }
        refresh(force: true)
    }

    @objc private func removeFeed(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        FeedStore.remove(url: url)
        if FeedStore.load().isEmpty { model.events = [] }
        refresh(force: true)
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

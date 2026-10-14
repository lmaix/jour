<img src="screenshots/icon.png" width="96" alt="">

# Jour

A macOS menu bar app: a calendar icon showing today's date, and on click a
popover with the month (a dot under busy days) and the next five events,
pulled from your Google calendars through their iCal feeds. Native macOS
look (accent color, light/dark).

<img src="screenshots/popover.png" width="442" alt="Popover">

## Install

1. Download **Jour-x.y.zip** from the
   [latest release](https://github.com/lmaix/jour/releases/latest).
2. Unzip it and drag **Jour.app** to your **Applications** folder.

The app is signed and notarized: it launches without a Gatekeeper warning.

### Build from source

```bash
./build.sh
```

Runs the tests, compiles `Jour.app`, installs it in `~/Applications`,
launches it and registers it to start at login. No dependency beyond Xcode
(or the Command Line Tools, `xcode-select --install`). `release.sh` builds
the signed, notarized universal zip published in the releases.

## Add a calendar

1. Google Calendar (web) → Settings → your calendar in the left column →
   "Integrate calendar" section → **Secret address in iCal format** → copy.
2. Right-click the menu bar icon → **Ajouter un agenda iCal…** → paste the
   URL, pick a name (optional) and a color.

Repeat for each calendar (personal, work…). These URLs are secrets: they
grant read access to the calendar, and they are stored in your Keychain.
Any other `.ics` / `webcal://` URL works too.

## Use

- Left click: the calendar. ‹ › switch months, clicking the title returns
  to today.
- Below the grid: the next 5 events (ongoing or upcoming) with "Aujourd'hui",
  "Demain" or the date. Click a day to see its events; click it again to go
  back to the upcoming list.
- Right click: list of calendars (remove), add, refresh, quit.

## Limitations

- Google caches the iCal feed: a change can take minutes to hours to show
  up. The app refreshes every 5 minutes, when the popover opens (30 s
  minimum) and when the month changes.
- Recurrences expanded by the app: daily, weekly (BYDAY), monthly (day of
  month, nth weekday), yearly, INTERVAL, COUNT, UNTIL, EXDATE and modified
  occurrences (RECURRENCE-ID). Exotic rules (BYSETPOS, BYWEEKNO…) are not
  handled.
- Cancelled events are ignored; so are events you declined, when the Google
  URL contains your address (the case for primary calendars).

## Uninstall

Quit the app (right-click the icon → Quitter), delete
`~/Applications/Jour.app`, and remove the "Jour" item from your Keychain.

## License

[MIT](LICENSE)

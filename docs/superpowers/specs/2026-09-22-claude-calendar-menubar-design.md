# ClaudeCalendarBar — design (v2, flux iCal)

App macOS native de barre de menus affichant les événements de plusieurs
agendas Google via leurs « adresses secrètes au format iCal ».

## Affichage (validé)
- Barre de menus : icône calendrier (image template) avec le numéro du jour.
- Clic gauche : popover 340 pt, apparence native, police monospace. En-tête
  ‹ mois année › (clic = aujourd'hui), ligne lun→dim, grille 6×7 (hors mois
  grisé, aujourd'hui en cercle accent, jour sélectionné en cercle gris, point
  accent sous les jours avec événements). Sous la grille : « À venir », les 5
  prochains événements (en cours ou futurs) avec Aujourd'hui / Demain / date
  courte + heure ; clic sur un jour → événements de ce jour, bouton « À venir ».
  Ligne d'erreur en pied.
- Clic droit : « Retirer « nom » » par agenda (pastille couleur), Ajouter un
  agenda iCal… (URL, nom facultatif, couleur parmi 9 couleurs système),
  Actualiser, Quitter. Lancement au login automatique.

## Données
- Chaque agenda = une URL .ics (webcal:// accepté). Téléchargement sans cache,
  parsing ICS maison (`ICS.swift`, pur) : dépliage des lignes, VEVENT (UID,
  SUMMARY, LOCATION, STATUS, DTSTART/DTEND/DURATION avec TZID, VALUE=DATE, Z),
  RRULE (DAILY/WEEKLY+BYDAY/MONTHLY+BYDAY|BYMONTHDAY/YEARLY, INTERVAL, COUNT,
  UNTIL), EXDATE, RECURRENCE-ID, ATTENDEE PARTSTAT=DECLINED.
- Développement des occurrences sur la plage [grille visible ∪ aujourd'hui+31 j]
  dans le fuseau de l'événement (heure locale stable à travers l'heure d'été).
  Annulés exclus ; déclinés exclus si l'email extrait de l'URL Google
  correspond à l'ATTENDEE.
- Index par jour (multi-jours répétés, fin exclusive), liste « À venir »
  dédupliquée. Rafraîchissement : 5 min, ouverture (≥ 30 s), changement de
  mois, réveil.

## Stockage
- Un seul item Trousseau `ClaudeCalendarBar`/`feeds` : JSON `[{name, url,
  colorHex}]`.

## Historique
- v1 (API Google Calendar + OAuth PKCE) abandonnée : Stéphane ne voulait pas
  créer de projet Google Cloud. Le code OAuth a été retiré.

## Structure
- `Sources/Models.swift` (modèles, grille, index, formats), `ICS.swift`,
  `Feeds.swift` (Feed, FeedStore Trousseau, FeedFetcher), `StatusIcon.swift`,
  `CalendarView.swift` (SwiftUI), `main.swift`. `Tests/main.swift`, `build.sh`.

# ClaudeCalendarBar — design

App macOS native de barre de menus affichant les événements Google Agenda de
plusieurs comptes.

## Affichage (validé)
- Barre de menus : icône calendrier (image template) avec le numéro du jour.
- Clic gauche : popover 340 pt, apparence native (couleur d'accentuation,
  clair/sombre), police monospace. En-tête ‹ mois année › (clic sur le titre =
  aujourd'hui), ligne lun→dim, grille 6×7 (jours hors mois grisés, aujourd'hui
  en cercle teinté, jour sélectionné en cercle plein, point sous les jours avec
  événements), puis titre du jour et liste : barre de couleur de l'agenda,
  heure ou « Journée », titre, « Agenda · lieu ». Erreurs en pied de popover.
- Clic droit : menu « Retirer <compte> », Ajouter un compte Google…,
  Configurer l'identifiant OAuth…, Actualiser, Quitter. Lancement au login
  automatique.

## Données
- API Google Calendar v3 : `users/me/calendarList` (agendas cochés) puis
  `calendars/{id}/events?singleEvents=true&orderBy=startTime` sur la plage des
  42 cellules affichées. Événements annulés ou déclinés ignorés. Couleur =
  `colorId` (palette Google) sinon `backgroundColor` de l'agenda.
- Index par jour (multi-jours répétés, fin exclusive), tri journée entière puis
  heure. Rafraîchissement : 5 min, ouverture du popover (≥ 30 s), changement de
  mois, réveil.

## Authentification
- OAuth 2.0 « application de bureau » : PKCE S256, `NWListener` sur
  127.0.0.1:port aléatoire, `access_type=offline&prompt=consent`, échange du
  code sur oauth2.googleapis.com/token, email via userinfo.
- Trousseau : `ClaudeCalendarBar-client`/`client` = JSON {id, secret} ;
  `ClaudeCalendarBar`/<email> = refresh token. Access tokens en mémoire.
- Prérequis utilisateur : projet Google Cloud, API Calendar, écran de
  consentement en production, identifiant « Application de bureau ».

## Structure
- `Sources/Models.swift` (modèles, parsing Google, grille, index, formats —
  pur, testé), `Keychain.swift`, `GoogleAuth.swift`, `GoogleCalendarAPI.swift`,
  `StatusIcon.swift`, `CalendarView.swift` (SwiftUI), `main.swift`.
- `Tests/main.swift`, `build.sh`.

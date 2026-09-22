# ClaudeCalendarBar

App macOS de barre de menus : une icône calendrier avec le numéro du jour, et
au clic un popover avec le mois (points sous les jours occupés) et les
événements du jour sélectionné, tirés de tes agendas Google (plusieurs comptes).
Apparence native macOS (couleur d'accentuation, clair/sombre).

## Installation

```bash
./build.sh
```

Compile, lance les tests, installe `~/Applications/ClaudeCalendarBar.app`, la
démarre et l'inscrit au lancement à l'ouverture de session. Aucune dépendance
en dehors de Xcode.

## Côté Google (une seule fois)

1. [console.cloud.google.com](https://console.cloud.google.com) → crée un projet.
2. **API et services → Bibliothèque** → active « Google Calendar API ».
3. **Écran de consentement OAuth** : type Externe, remplis le nom, puis passe
   l'application **en production** (bouton « Publier »). Sans ça, Google
   invalide les refresh tokens au bout de 7 jours.
4. **Identifiants → Créer → ID client OAuth → Application de bureau**. Note
   l'ID client et le secret.

## Dans l'app

- Clic droit sur l'icône → **Configurer l'identifiant OAuth…** → colle l'ID et
  le secret (stockés dans ton Trousseau).
- **Ajouter un compte Google…** ouvre le navigateur ; connecte-toi, autorise la
  lecture des agendas. Répète pour le second compte.
- Clic gauche → le calendrier. ‹ › changent de mois, clic sur le titre du mois
  revient à aujourd'hui, clic sur un jour affiche ses événements.

## Détails

- Lecture seule (`calendar.readonly`). Tous les agendas cochés dans Google
  Agenda sont pris en compte ; les événements annulés ou déclinés sont ignorés.
- Rafraîchissement toutes les 5 min, à l'ouverture du popover (30 s min entre
  deux) et au changement de mois.
- OAuth « application de bureau » avec PKCE et redirection locale
  (`http://127.0.0.1:<port>`). Refresh tokens dans le Trousseau, service
  `ClaudeCalendarBar`.
- Couleur de la barre d'un événement : celle de l'agenda Google (ou la couleur
  propre de l'événement).

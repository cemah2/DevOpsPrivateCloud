# Royaume `master` de Keycloak — réglages faits à la main

| | |
|---|---|
| Pourquoi à la main | OpenTofu n'a aucun droit sur `master` (`svc-tofu-keycloak` n'administre que `medisphere`, M24-E08) : c'est voulu, `master` contient les comptes qui administrent Keycloak lui-même |
| Qui modifie | `<MOI>-admin` (OTP), avec `kc-secours` essayé avant et après (RB-240) |
| Contrôle | `lab/bin/check 24 04` et `24 27` (lecture SQL sur `idp01`) ; revue semestrielle par Sophie Laurent |

## Réglages

| Écran (console 26.x) | Réglage | Valeur | Raison | Date | Ticket |
|---|---|---|---|---|---|
| *Realm settings* → *Security defenses* → *Brute force detection* | Mode | **Lockout temporarily** (5 échecs, attente 60 s doublée jusqu'à 15 min, remise à zéro 12 h) | protéger `<MOI>-admin` et `kc-secours` sans pouvoir les désactiver définitivement à distance | <AAAA-MM-JJ> | SEC-2527 |
| *Authentication* → *Policies* → *Password policy* | Politique | `length(16) and notUsername and passwordHistory(6)` | comptes d'administration ; pas d'expiration forcée (`kc-secours` ne doit pas exiger un changement le jour du bris de glace) | <AAAA-MM-JJ> | SEC-2527 |
| *Realm settings* → *Sessions* | Session SSO inactive / maximale | 30 min / 8 h | une session d'administration oubliée se ferme | <AAAA-MM-JJ> | SEC-2527 |
| *Realm settings* → *Tokens* | Jeton d'accès | 1 min (défaut de `master`) | inchangé : la console le rafraîchit | — | — |
| *Users* | Comptes | `<MOI>-admin` (OTP), `kc-secours` ; **aucun autre** | E04 | <AAAA-MM-JJ> | PLAT-2504 |
| *Clients* | `svc-tofu-keycloak` | rôles de `medisphere-realm` sauf `impersonation` | E08 | <AAAA-MM-JJ> | PLAT-2508 |
| Serveur (`keycloak.conf`) | `features-disabled` | `impersonation` | E27 (s'applique à tous les royaumes) | <AAAA-MM-JJ> | SEC-2527 |

## Historique

| Date | Qui | Changement | Ticket |
|---|---|---|---|
| <AAAA-MM-JJ> | <MOI> | Création du document, réglages ci-dessus | SEC-2527 |

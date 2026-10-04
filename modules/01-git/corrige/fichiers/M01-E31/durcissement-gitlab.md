# Durcissement de la forge GitLab — `git01`

> Exemple de livrable M01-E31 (SEC-258), à ranger dans `docs/socle/securite/durcissement-gitlab.md`
> de `plateforme/medisphere`. Application : `forge/durcissement/durcir-gitlab.sh` (réglages en base),
> `gitlab.rb` (serveur web), rôle Ansible au M04 (système).

| | |
|---|---|
| Version | GitLab CE 19.4.x, Debian 13 |
| Date | AAAA-MM-JJ |
| Relu par | Sophie Laurent (RSSI), Karim Benali |
| Prochaine revue | à chaque mise à jour mineure de GitLab (RB-011) et au plus tard dans 6 mois |

## Modèle de menace retenu

1. Vol d'identifiants d'un membre de l'équipe (hameçonnage, réutilisation de mot de passe).
2. Jeton divulgué (dépôt, journal de CI, poste perdu).
3. Compte administrateur détourné ou session administrateur oubliée ouverte.
4. Code ou secret rendu visible au-delà de l'équipe (projet public, export).
5. Fuite de métadonnées vers des tiers (souveraineté, HDS).
6. Abus du serveur depuis le réseau (force brute, SSRF par webhooks).
7. Exécution de code arbitraire par un pipeline sur le runner (exécuteur shell).

## Mesures

| # | Mesure | Menace | Coût pour l'équipe | Vérification |
|---|---|---|---|---|
| 1 | Inscriptions fermées (`signup_enabled=false`) | 1, 4 | création des comptes par un admin | `durcir-gitlab.sh --verifier` |
| 2 | 2FA obligatoire, délai de grâce 48 h | 1 | enrôlement TOTP ; codes de secours à ranger | idem + tentative de connexion |
| 3 | Admin Mode | 3 | réauthentification avant chaque tâche d'admin ; jetons d'admin avec portée `admin_mode` | idem |
| 4 | Git HTTPS sans mot de passe (jetons seulement) | 1, 2 | chaque poste utilise un jeton ou SSH | `git clone https://…` avec mot de passe refusé |
| 5 | Pas de « se souvenir de moi », sessions de 8 h | 3 | reconnexion quotidienne | idem |
| 6 | Visibilité publique interdite, défauts privés | 4 | aucun | idem + aucun projet public |
| 7 | Clés SSH : DSA interdit, RSA ≥ 3072, ECDSA ≥ 256 | 1 | régénérer les vieilles clés RSA 2048 | ajout d'une clé RSA 2048 refusé |
| 8 | Jetons d'enregistrement de runner désactivés | 7 | seul le flux `glrt-` (E23) | idem |
| 9 | Service Ping, vérification de version, Gravatar, Snowplow désactivés | 5 | veille des versions à faire autrement : abonnement aux annonces de sécurité de GitLab (RB-011) | idem |
| 10 | Requêtes vers le réseau local interdites aux webhooks et hooks système | 6 | une intégration interne devra être autorisée explicitement (`outbound_local_requests_whitelist`) | idem |
| 11 | Limitation de débit des requêtes non authentifiées (API 300/min, web 600/min) | 6 | aucun en usage normal | idem |
| 12 | TLS 1.2/1.3, HSTS, redirection HTTPS | 6 | aucun | `curl -sI`, `openssl s_client -tls1_1` refusé |
| 13 | SSH de `git01` : clé uniquement, pas de `root` (M00) ; utilisateur `git` réservé à gitlab-shell | 1 | aucun | `sshd -T` |
| 14 | Hooks serveur (E26) et pipeline obligatoire (E24) | 2, 4 | aucun au quotidien | checks E24, E26 |
| 15 | Jetons : expiration obligatoire, inventaire trimestriel, rotation documentée | 2 | rotation des jetons de bots (RB) | *Admin → Credentials* (Premium) indisponible : script d'inventaire par l'API `personal_access_tokens` |
| 16 | Sauvegardes chiffrées hors site (E28) | toutes | aucun | check E28 |

## Ce qui n'a pas été fait, et pourquoi

| Mesure écartée ou reportée | Raison |
|---|---|
| Désactivation automatique des comptes dormants | les comptes des personnages ne se connectent jamais (ils servent par jetons d'emprunt d'identité) : ils seraient désactivés ; à activer quand les comptes seront fédérés (M24) |
| SSO / clés matérielles (WebAuthn) | M24 (Keycloak) |
| Exécuteur isolé (conteneurs, VM éphémères) pour la CI | M12/M19 ; en attendant, runner limité aux projets internes, utilisateur sans `sudo`, secrets en variables protégées |
| Politique de mot de passe avancée, limite de durée des jetons personnalisable, journal d'audit complet | fonctions Premium/Ultimate |

## Effets de bord traités

- **Admin Mode** : les jetons d'un administrateur perdent l'accès aux points d'API d'administration. Le jeton des checks (`read_api`) et le jeton d'administration (`api`) ont été recréés avec la portée supplémentaire `admin_mode` (fichiers dans `~/.config/workbook/`, mêmes noms).
- **2FA** : `root` (bris de glace) enrôlé, codes de secours sous enveloppe scellée (coffre de l'équipe) ; les comptes des personnages ne se connectent pas à l'interface (jetons seulement), la 2FA ne les gêne pas.
- **Session de 8 h** : nécessite un redémarrage de GitLab (`gitlab-ctl restart puma`), fait le AAAA-MM-JJ.

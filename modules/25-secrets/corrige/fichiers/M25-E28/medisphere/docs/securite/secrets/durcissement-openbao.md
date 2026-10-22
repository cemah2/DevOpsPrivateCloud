# Durcissement d'OpenBao — preuves

> `docs/securite/secrets/durcissement-openbao.md` — M25-E28 (SEC-2628). Réponse point par point au rapport de pré-audit.

| Point du rapport | Mesure | Preuve (commande) |
|---|---|---|
| Jeton racine initial dans un historique ; pas de procédure | Jeton révoqué (E08) ; plus aucun jeton racine ; procédure écrite et répétée (`procedure-jeton-racine.md`) ; alerte `OpenBaoJetonRacineUtilise` | Loki (audit) : `count_over_time({service="openbao"} |= `"policies":["root"]` [24h])` = 0 hors séance ; accessors : `bao list auth/token/accessors` puis `bao token lookup -accessor` (aucune politique `root`) |
| `secret_id` transmis en clair | Enveloppement (5 min, usage unique) pour `medictl` et `openbao-instantanes` (`outils/secret-id-enveloppe.sh`, rôle `openbao_instantane`) | Loki : réponses de `auth/approle/role/<rôle>/secret-id` toutes avec `wrap_info` ; `bao write sys/wrapping/lookup token=…` |
| Unité par défaut du paquet | Surcharge `medisphere.conf` : `ProtectSystem=strict`, chemins inscriptibles limités, protections du noyau, `SystemCallFilter=@system-service`, `MemoryDenyWriteExecute` | `systemd-analyze security openbao.service` : `<SCORE-AVANT>` → `<SCORE-APRÈS>` ; `systemctl show openbao -p ProtectSystem -p ReadWritePaths` |
| TLS 1.2 accepté | `tls_min_version = "tls13"` | `openssl s_client -connect vault01.par1.medisphere.internal:8200 -tls1_2 </dev/null` → `alert protocol version` ; `-tls1_3` → `TLSv1.3` |
| Pas de limite de baux ni de débit | `default_lease_ttl = 1h`, `max_lease_ttl = 24h` ; `tune` explicite par méthode (oidc 8 h, approle 1 h, gitlab 1 h, k8s-par1 24 h) et `pki-services` 72 h ; quotas `global` (200/s) et `approle-connexion` (10/min, blocage 5 min) | `bao read sys/auth/approle/tune` ; `bao list sys/quotas/rate-limit` ; boucle de connexions fautives → `429` |

En plus : point d'accès non authentifié de génération du jeton racine désactivé explicitement (`disable_unauthed_generate_root_endpoints = true`) ; en-têtes `X-Content-Type-Options` et `X-Frame-Options` sur l'API (HSTS et `Cache-Control: no-store` étaient déjà envoyés).

Effet de bord à connaître : les baux déjà émis gardent leur durée ; ils sont plafonnés au prochain renouvellement. Un jeton périodique est aussi plafonné par le maximum de son montage (vérifié sur `kms01`).

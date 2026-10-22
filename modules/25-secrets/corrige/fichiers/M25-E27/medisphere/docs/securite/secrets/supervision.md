# Supervision du coffre OpenBao

> `docs/securite/secrets/supervision.md` — M25-E27 (PLAT-2627).

## Exposition des métriques : décision

| Option | Ce qui est exposé | Coût | Risque |
|---|---|---|---|
| **A. `unauthenticated_metrics_access = true`** sur l'écouteur (retenue) | `/v1/sys/metrics` sans jeton, en HTTPS, aux seules sources autorisées par le pare-feu (travailleurs, `mon01`, MGMT) | aucun secret à gérer ; marche aussi sur un nœud **scellé** (c'est quand on en a besoin) | les métriques révèlent l'activité (volumes de requêtes, nombre de baux, noms de montages dans certaines séries) : filtrage réseau obligatoire |
| B. Jeton de lecture (politique `read` sur `sys/metrics`) dans un Secret de `supervision` | idem, à qui a le jeton | un jeton de plus à renouveler (périodique), un Secret de plus ; un nœud scellé ne valide aucun jeton : **plus de métriques au moment où on en a besoin** | fuite du jeton = lecture des métriques seulement |

Décision : A, pour que la supervision voie un nœud scellé ; compensations : écoute filtrée par le pare-feu local des quatre nœuds et la bordure, aucune donnée sensible dans les métriques (vérifié : pas de chemins de secrets ni d'identités), relecture à chaque montée de version.

## Ce qui est surveillé

| Alerte | Gravité | Expression (résumé) | Runbook |
|---|---|---|---|
| `OpenBaoScelle` | critique | `vault_core_unsealed` à 0 (max par nœud) **ou** `up == 0`, 2 min | RB-251 |
| `OpenBaoSansLeader` | critique | aucun `vault_core_active` à 1 parmi `vault01-03`, 1 min | RB-251 |
| `OpenBaoToleranceNulle` | avertissement | `vault_autopilot_failure_tolerance` < 1, 10 min | RB-251 |
| `OpenBaoAuditEnEchec` | critique | augmentation de `vault_audit_log_request_failure` sur 5 min | RB-251 |
| `OpenBaoBauxNombreux` | avertissement | `vault_expire_num_leases` > 5 000, 15 min | RB-251 |
| `OpenBaoInstantaneEnRetard` | avertissement | dernier instantané > 2 h (collecteur textfile) | RB-252 |
| `CertificatServicesExpireBientot` | avertissement | certificat émis par `openbao-services` à moins de 12 h de l'échéance | RB-251 |

Sondes extérieures (`mon01`) : VIP (`https_2xx`, 200 attendu) et chaque nœud (`openbao_sante`, 200 ou 429).

## Ce qui n'est pas surveillé (et pourquoi)

- La durée restante du jeton du seal `transit` : aucune métrique ; le serveur le renouvelle, et RB-251 § 3 explique le contrôle manuel (`bao token lookup -accessor`). Le risque réel (grappe arrêtée plus longtemps que la période) est couvert par `OpenBaoSansLeader`.
- Les accès aux secrets : c'est l'audit (Loki, locataire `audit`, M25-E21), pas les métriques.

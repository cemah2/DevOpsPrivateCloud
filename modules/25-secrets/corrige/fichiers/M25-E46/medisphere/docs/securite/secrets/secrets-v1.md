# Les secrets de MédiSphère v1 — fiche de livraison

> M25-E46 (PLAT-2646). Étiquette `secrets-v1` de `plateforme/medisphere`. Modèle du corrigé : complète
> les `<…>` et retire ce que ton lab ne fait pas. Aucune valeur : des emplacements.

## Ce qui est livré

| Brique | État | Où |
|---|---|---|
| Coffre | OpenBao 2.7.1, grappe Raft `vault01-03`, VIP `openbao.par1.medisphere.internal:8200` (VRID 120), seal `transit` par `kms01`, unité durcie, TLS 1.3, audit déclaré → Loki `audit` | `plateforme/ansible` (rôles `openbao`, `openbao_kms`, `openbao_instantane`), ADR-0250 |
| Configuration | politiques, méthodes, rôles, moteurs, quotas, PKI : `tofu plan` vide sur `main`, test des politiques en CI | `plateforme/secrets` |
| Identités | personnes : OIDC (groupes externes) ; CI : JWT `gitlab/` (`ref_protected`) ; pods : `k8s-par1` (audience) ; machines : AppRole (`secret_id` enveloppés) | `plateforme/secrets/tofu/` |
| Secrets statiques | KV v2 `kv/plateforme/…`, `kv/<application>/<env>/…`, livrés par ESO (ClusterSecretStore `openbao`, SecretStore par espace), lookups Ansible | `plateforme/gitops`, dépôts de déploiement |
| Secrets dynamiques | PostgreSQL de MédiAgenda recette **et prod** (rôles `mediagenda-api`, `mediagenda-migrateur`, 1 h), générateur `VaultDynamicSecret`, Reloader | `db-mediagenda/` |
| Chiffrement | `transit/` : `sops-plateforme`, `cosign-medisphere` (non exportable), `medictl-donnees` | `tofu/transit.tf` |
| Certificats | « MédiSphère Services CA » (`pki-services/`), ClusterIssuer `openbao-services`, mTLS MédiAgenda → MédiDoc (recette), CRL sondée | `tofu/pki-services.tf`, `plateforme/k8s` |
| Reprise | instantanés horaires chiffrés `age` → `s3-01/openbao-instantanes` (30 j), restauration éprouvée : RPO `<…>` min, RTO `<…>` min (`<date>`) | RB-252 |
| Supervision | `regles/secrets.yaml`, `regles/pki-services.yaml`, `regles/autodescellement.yaml` ; tableau `plateforme-openbao` ; sonde `sys/health` depuis `mon01` | `plateforme/observabilite` |
| Runbooks | RB-250 (fuite), RB-251 (descellement), RB-252 (sauvegarde), RB-253 (montée de version), RB-254 (rotation), RB-255 (coffre fermé) | `docs/securite/secrets/runbooks/` |

## Couverture de l'inventaire

`inventaire-secrets.md` : `<N>` secrets recensés ; `<n1>` dans le coffre (KV), `<n2>` remplacés par une
identité, `<n3>` dynamiques, `<n4>` en transit ou en PKI, `<n5>` **amorçage** justifié, `<n6>` reste à
faire daté. `secrets-k8s.sh` est retiré : la racine publique d'amorçage du runner (seule ligne
restante) est posée par `<le rôle / l'objet qui la remplace>`.

## Amorçage : ce qui reste hors du coffre, et pourquoi

| Élément | Raison | Garde |
|---|---|---|
| Vault Ansible `critique` (bris de glace, `admin.conf`, comptes de secours) | doit être lisible coffre fermé | identité `critique`, deux personnes |
| clés de récupération de la grappe, parts de `kms01` | ouvrent le coffre | `age` par dépositaire, support hors ligne |
| clé privée `age` de restauration des instantanés | lire une sauvegarde quand le coffre est perdu | Vault `critique` + papier |
| racine « MédiSphère Root CA » | cérémonies | hors ligne (M06) |
| identité initiale d'ESO (compte de service et racine publique) | ESO doit joindre le coffre avant tout Secret | objets versionnés, aucun secret |

## Limites assumées (non couvert)

- **Un seul `kms01`**, sur le même hyperviseur que la grappe : sa perte définitive impose la migration
  vers Shamir avec les clés de récupération (RB-251). Seal HA et HSM : options de l'ADR-0250.
- **Un seul site** : pas de réplication du coffre vers PAR2 (F5).
- **etcd** chiffré par `secretbox` (clé sur les nœuds de contrôle) : aucun plugin KMS v2 maintenu pour
  OpenBao (ADR-0251) ; la KEK de `ceph-rbd-chiffre` reste dans le cluster.
- **Pas de contrôle à deux personnes** sur la lecture des secrets de production (*Control Groups* non
  mis en place) : compensé par l'audit et sa revue mensuelle.
- **Pas de SIEM** : l'audit est dans Loki (un an), interrogé à la main ou par alertes du ruler.
- Rotations **inscrites mais non automatisées** : jetons Proxmox, clés WireGuard, clés cephx,
  identités S3 (politique de rotation, E33).
- Promesses non tenues ici : `<liste, avec leur raison et le module ou le final qui les reprend>`.

## Ce que consomment le M26 et les finaux

| Consommateur | Ce qu'il prend | Où |
|---|---|---|
| M26 (Kyverno, `ImageValidatingPolicy`) | clé **publique** Cosign | `docs/registre/cosign.pub` (ancienne : `cosign-m13.pub`) |
| M26 (Kyverno) | identifiant de lecture Harbor | `kv/plateforme/kyverno/harbor` par ESO |
| M26 (Falco, auditeur HDS) | journal d'audit d'OpenBao | Loki locataire `audit`, `{service="openbao"}` |
| M27 (données, messagerie) | identifiants dynamiques et KV pour les nouvelles bases et files | même modèle que `db-mediagenda/` |
| F1, F5 | reconstruction et reprise du coffre | RB-251, RB-252, RB-255, instantanés |
| F6 | preuves d'audit, revue des accès | `preuves-audit.md`, requêtes Loki |

## Démonstration de la revue (préparée)

Voir `demonstration-secrets-v1.md` : un scénario par type de secret (statique, dynamique, client
OIDC), chacun avec la rotation, la preuve sans coupure, la preuve que l'ancienne valeur est refusée,
la requête d'audit des sept derniers jours.

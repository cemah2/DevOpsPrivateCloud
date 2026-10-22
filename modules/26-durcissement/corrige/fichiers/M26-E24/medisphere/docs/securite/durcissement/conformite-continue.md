# Conformité continue du parc

| | |
|---|---|
| Ticket | SEC-2724 (complété par SEC-2728 : section « Traces ») |
| Exercices | M26-E24, M26-E28 |
| Propriétaire | Équipe Plateforme ; lecture : RSSI (Sophie Laurent) |
| Dernière revue | <DATE> |

## Ce qui est mesuré

| Mesure | Outil | Référentiel | Profil |
|---|---|---|---|
| Configuration des hôtes Debian 13 | OpenSCAP 1.4 + ComplianceAsCode 0.1.82 (`ssg-debian13-ds.xml`) | CIS Debian 13 v1.0.0 niveau 1 serveur ; ANSSI-BP-028 intermédiaire | `cis_level1_server`, `anssi_bp28_intermediary`, **adaptés** par `/etc/durcissement/tailoring.xml` |
| Configuration des hôtes Rocky 10 (`ipa01`, `ceph01-03`) | OpenSCAP 1.4 + `scap-security-guide` 0.1.82 d'AppStream | CIS RHEL 10 v1.0.1 niveau 1 serveur ; ANSSI-BP-028 intermédiaire | `cis_server_l1`, `anssi_bp28_intermediary`, adaptés |
| Indice de durcissement | Lynis 3.1.7 | aucun (indice maison de Lynis) | — |

Le **profil adapté** (*tailoring*) est généré par le rôle `durcissement` à partir de `durcissement_exceptions` : chaque exception signée du registre (`exceptions.md`) y désélectionne la règle concernée. Le score publié est donc « hors exceptions signées ». Les règles désélectionnées apparaissent dans l'ARF en `notselected`, ce qui permet de prouver à l'auditeur **lesquelles** ont été écartées, et pourquoi (registre).

Hôtes couverts : toutes les VMs du socle (inventaire `socle`) et les six nœuds de `k8s-par1`. Hors périmètre : `pve01` et `pbs01` (hôtes physiques, mesure manuelle trimestrielle), `gw01`/`gw02` couverts mais avec les exceptions de routage (`ip_forward`).

## Quand

Chaque dimanche à 03:30, décalé d'une durée aléatoire **fixe** par hôte (jusqu'à 30 min, `FixedRandomDelay`) ; une machine éteinte à l'heure prévue s'analyse au démarrage suivant (`Persistent=true`). Durée mesurée : ~6 min et ~350 Mio par référentiel sur `mon01` (à remplacer par tes mesures) ; l'unité est bridée (`Nice=19`, E/S en `idle`, `CPUQuota=50%`, `MemoryMax=1G`).

## Où vont les résultats, qui peut les lire

| Résultat | Où | Durée de conservation |
|---|---|---|
| ARF (XML, toutes les règles et leurs preuves), compressé | `s3-01`, compartiment `conformite`, `AAAA-MM-JJ/<hôte>/<référentiel>-arf.xml.gz` | 3 ans (exigence HDS de traçabilité ; purge manuelle annuelle, compartiment versionné) |
| Rapport HTML, compressé | même dossier, `<référentiel>-rapport.html.gz` | 3 ans |
| `lynis-report.dat`, compressé | même dossier | 1 an |
| Métriques | Prometheus (15 j), Thanos (5 min : 180 j ; 1 h : 2 ans) | 2 ans |

Identités S3 : `conformite` (VMs) écrit et liste, ne lit ni ne supprime ; `conformite-lecture` (RSSI, audit, checks) lit et liste. Une VM compromise peut écraser l'objet d'une autre (SeaweedFS ne restreint pas par préfixe) : le **versionnage** du compartiment conserve la version précédente, et l'écart de score déclenche `ConformiteDegradee`.

## Métriques

| Série | Signification |
|---|---|
| `medisphere_conformite_score{referentiel}` | score XCCDF (0-100, méthode par défaut) de la dernière analyse réussie |
| `medisphere_conformite_regles{referentiel,resultat}` | nombre de règles `pass`, `fail`, `notapplicable`, `notselected`, `error`, `unknown`, `notchecked` |
| `medisphere_conformite_derniere_analyse_secondes{referentiel}` | horodatage de la dernière analyse réussie |
| `medisphere_conformite_duree_secondes{referentiel}` | durée de l'analyse (suivi de la charge) |
| `medisphere_lynis_indice` | indice Lynis |

Fichier `/var/lib/prometheus/node-exporter/conformite.prom`, écrit atomiquement ; lu par le rôle `node_exporter` (VMs) et par le DaemonSet node-exporter de `kps` (nœuds, montage en lecture seule).

## Alertes (`plateforme/observabilite`, `regles/conformite.yaml`)

| Alerte | Condition | Gravité |
|---|---|---|
| `ConformiteDegradee` | score inférieur de plus de 5 points à celui de l'analyse précédente, pendant 1 h | avertissement |
| `ConformiteSousObjectif` | score sous l'objectif du référentiel (CIS : 85, ANSSI intermédiaire : 75), pendant 1 h | avertissement |
| `ConformiteAnalyseAbsente` | analyse de plus de 8 jours, hôte supervisé jamais analysé, ou un seul référentiel sur deux, pendant 6 h | avertissement |
| `LynisIndiceBas` | indice sous 70 | info |

Aucune n'est critique : une dérive de conformité ne réveille personne la nuit ; elle est traitée en heures ouvrées, avant la revue hebdomadaire.

## Pourquoi pas seulement un score

- Un score **stable** peut cacher une dérive : une règle corrigée et une autre cassée la même semaine s'annulent. Le compte `fail` et la comparaison des ARF de deux semaines montrent les règles qui ont **changé** d'état.
- L'**ARF** est la preuve : il contient, pour chaque règle, le résultat et les éléments observés (OVAL), la version du contenu et du profil adapté. Un score n'est qu'un résumé ; l'auditeur demande la preuve.
- Le score XCCDF par défaut pondère les règles : il n'est comparable qu'entre deux analyses du **même** profil adapté. Toute modification du registre des exceptions est notée dans le rapport de la semaine (`rapports/`).

## Revue

Chaque lundi : tableau « Sécurité — Conformité » (Grafana, dossier Sécurité), alertes de la semaine, nouvelles règles en échec. Chaque trimestre : purge éventuelle, mise à jour de ComplianceAsCode (nouvelle version → nouvelles règles : baisse de score attendue, annoncée).

## Traces (M26-E28)

| Trace | Où | Combien de temps | Qui la lit |
|---|---|---|---|
| Journal d'audit de l'API (fichier local) | `/var/log/kubernetes/audit/` des nœuds de contrôle | 30 jours, 10 fichiers de 100 Mo compressés au plus | Plateforme (sudo sur les nœuds) |
| Journal d'audit de l'API (centralisé) | Loki, locataire `audit` (`{job="kubernetes-audit"}`) | 1 an (rétention du locataire) | Sécurité, Plateforme (organisation Grafana « Sécurité ») |
| auditd des VMs, Falco, Tetragon, OpenBao | Loki, locataire `audit` (`service="auditd"`, `"falco"`, `"tetragon"`, journal d'OpenBao) | 1 an | idem |
| Résultats de conformité | `s3-01`, compartiment `conformite` | 3 ans | RSSI, audit |

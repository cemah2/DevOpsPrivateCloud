# RB-354 — Réplication vers PAR2 : surveiller, réparer, couper, inverser

| | |
|---|---|
| Ticket | PLAT-3504 (CHG-3504 pour les changements de PAR1) |
| Flux | objets (`filer.sync`), MédiDoc (`rclone`), Git (*push mirrors*), images (`cosign copy`), base (archive des WAL : S06) |
| Mesures | `docs/pra/mesures/retard-replication.md` ; alertes `pra-replication` du témoin de `mon01` |

## 1. Principes

1. **Une copie n'est pas une sauvegarde.** `filer.sync` et `rclone sync` répliquent les écritures **et les suppressions** en secondes ou en minutes. Ce qui protège contre une suppression ou un chiffrement malveillant : **PBS** (sauvegardes des VMs, rétention), le **versionnage** des compartiments (`tofu-state`, `openbao-instantanes`, `medidoc-documents` de `s3-02`), et la rétention propre à chaque outil (archives CNPG 14 jours, Velero). Une purge sur `s3-01` doit se réparer depuis PBS ou depuis les versions, **jamais** en recopiant PAR2 vers PAR1 sans analyse.
2. **Le retard se mesure à l'arrivée** (âge du dernier objet sur `s3-02`), jamais par l'état du processus.
3. **PAR2 tire, PAR1 ne pousse pas** (sauf GitLab et la CI) : aucune identité de PAR2 ne peut écrire à PAR1.

## 2. Une alerte de retard

| Alerte | Diagnostic dans l'ordre |
|---|---|
| `PraWalMediagendaEnRetard` | (1) la base de PAR1 archive-t-elle ? `kubectl -n mediagenda-prod get cluster mediagenda-db -o jsonpath='{.status.conditions}'` (`ContinuousArchiving`) ; (2) l'objet est-il sur `s3-01` ? (3) `systemctl status seaweedfs-filer-sync@cnpg-k8s-par1` et `journalctl -u …` sur `s3-02` (erreurs gRPC, TLS, signature) ; (4) le chemin : `nc -vz 10.10.20.14 8888 18888` depuis `s3-02` ; (5) le disque de `s3-02` |
| `PraMedidocEnRetard` | `systemctl status medidoc-copie.service` ; identité RGW (lecture) ; certificat du RGW |
| `PraMiroirEnEcart` | GitLab, projet → *Settings → Repository → Mirroring repositories* : dernière erreur ; clé d'hôte de `adm02` changée ? clé du miroir dans `miroirs_git_cles_ecriture` ? |
| `PraImagesEnRetard` | dernier pipeline planifié de `plateforme/copie-par2` (journal du job : « REFUS » = image non signée, à traiter comme un incident de sécurité) |
| `PraExportateurPar2Muet` | `wg0` (bordure et `hp01`), VM arrêtée, node_exporter |

Redémarrer une unité `filer.sync` est sans risque : elle reprend à son dernier point de contrôle.

## 3. Ajouter ou retirer un compartiment

MR sur `host_vars/s3-02/replication_par2.yml` (`replication_par2_compartiments`), justification de minimisation (données de santé ? utile à une reprise ?), relecture de Sophie ; application du rôle ; mesure ajoutée à `pra-retards` si le flux compte pour un RPO.

## 4. Le jour d'un PRA (RB-350, vague 0)

- **Arrêter** les réplications entrantes : `systemctl stop 'seaweedfs-filer-sync@*' medidoc-copie.timer` sur `s3-02` (la source n'existe plus ; et si PAR1 revenait de façon intempestive, on ne veut pas qu'il écrase PAR2).
- Noter dans la main courante l'**âge des dernières données** de chaque flux (`/var/lib/prometheus/node-exporter/pra_replication.prom` sur `s3-02`) : c'est la base du RPO mesuré.
- Les miroirs de `adm02` deviennent la **forge** : on y pousse les changements du PRA (compte `admin` ajouté temporairement en écriture, RB-350 annexe) ; tout commit fait à PAR2 sera repoussé vers GitLab au retour (RB-351).

## 5. Au retour (RB-351)

Les flux s'inversent le temps du retour : PAR2 → PAR1 (`filer.sync -isActivePassive` lancé sur `s3-01`, `-a` = `s3-02`) pour ce qui a été écrit pendant le PRA (`cnpg-k8s-par2`, `medidoc-documents`), puis retour au sens normal. Les commits des miroirs de `adm02` sont repoussés vers GitLab (MR de rattrapage), **avant** la reprise des *push mirrors*, qui écraseraient sinon les branches de `adm02` (miroirs « forcés »).

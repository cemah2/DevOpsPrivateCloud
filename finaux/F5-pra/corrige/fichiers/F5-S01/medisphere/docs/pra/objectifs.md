# Objectifs de reprise — PRA v1

| | |
|---|---|
| Ticket | PLAT-3501 |
| Entrée | `bia.md` (même date) |
| Statut | Approuvé par Claire Morel le <AAAA-MM-JJ> |
| Révision | après chaque exercice (rapport `exercices/…/rapport.md`) et au plus tard un an après |

## 1. Hypothèses du PRA v1

- **Sinistre** : PAR1 entièrement perdu (salle, `pve01`, toutes ses VMs, ses disques et son réseau), d'un coup, sans préavis. PAR2 (`hp01`) intact, alimenté, joignable par Internet (son propre accès) ; le lien `wg0` est coupé.
- **Équipe** : au moins deux personnes de l'équipe Plateforme joignables en 30 min, dont une capable de suivre RB-350 ; l'enveloppe de reprise accessible en 1 h (`enveloppe.md`).
- **Hors hypothèse** (PRA v1 ne couvre pas) : perte simultanée de PAR1 et PAR2 (seules restent les sauvegardes hors site de l'enveloppe), rançongiciel qui aurait aussi atteint PAR2, indisponibilité de l'équipe.

## 2. Définitions et mesure

| Terme | Définition retenue |
|---|---|
| **T0** | instant du sinistre (exercice : heure posée par `lab/bin/break F5 09`, dans `/var/lib/workbook/f5-t0` de `adm02` et de `gw01`, et dans la main courante) |
| **T décision** | heure à laquelle Claire déclenche le PRA (main courante, `[décision]`) |
| **T reprise** (fin de l'horloge du RTO) | première **création réussie** d'un rendez-vous par le nom global `https://mediagenda.medisphere.internal`, réponse portant `X-MediSphere-Site: par2`, vue par la sonde `ms-sonde-pra` (`adm02`) **et** confirmée par Julien depuis un poste qui n'est pas dans le lab |
| **RTO** (objectif) | T reprise − T0, dans le pire cas accepté ; on mesure aussi T reprise − T décision (durée technique) |
| **RPO** (objectif) | pour MédiAgenda : horodatage du dernier témoin `PRA-TEMOIN` écrit à PAR1 − horodatage du dernier témoin retrouvé à PAR2 (S06) ; pour les autres : âge de la dernière donnée présente à PAR2 au moment de T0 |
| **Mode dégradé** | ce qui fonctionne à PAR2 pendant le PRA, ce qui est coupé, et pour combien de temps on l'accepte |

Le RTO est un **engagement** : il est inférieur à la DMIA de la BIA avec une marge ; idem RPO et PDMA.

## 3. Objectifs par service

| Service | RTO | RPO | DMIA / PDMA (BIA) | Capacité qui le rend tenable | Mode dégradé accepté pendant le PRA |
|---|---|---|---|---|---|
| **MédiAgenda** | **4 h** | **15 min** | 5 h / 1 h | base en réplica continu à PAR2 (topologie distribuée CNPG, archive copiée par `filer.sync`) ; cluster `k8s-par2` tiède, images sur `reg02`, secrets présents en veille ; RB-350 vagues 1 à 4 (≈ 2 h 30 de référence à confirmer à l'exercice) | une instance de l'API, une de la base (pas de réplica local : un incident à PAR2 = arrêt), Valkey vide au départ (cache), pas de canary, supervision minimale seulement (§4) ; latence p95 ≤ 1 s acceptée (SLO de 250 ms suspendu) ; extraction Data suspendue |
| **MédiDoc** | **8 h** | **1 h** | 1 jour / 4 h | copie de `medidoc-documents` vers `s3-02` toutes les 15 min (`rclone`), image sur `reg02` | une instance ; dépôts et lecture ; pas de mTLS vers MédiAgenda si l'autorité de services d'OpenBao n'est pas restaurée (décision écrite au déclenchement) |
| **Legacy-RDV** | **8 h** | **24 h** | 1 jour / 24 h | sauvegarde quotidienne de MariaDB (`mariadb-legacy-rdv`) et sauvegarde Velero des pièces jointes copiées sur `s3-02` ; restauration à la demande | une instance ; pièces jointes restaurées sur stockage local ; ressaisie de la journée par les cabinets |
| **MédiNotif** | **8 h** | messages en vol perdus | 8 h / — | définitions RabbitMQ en code, déployées à PAR2 au PRA ; rejeu des rappels du jour depuis MédiAgenda | un nœud RabbitMQ, pas de quorum (file quorum à un membre) ; rappels du soir avec retard |

**Pourquoi ces chiffres** (résumé, détail dans la BIA) :
- MédiAgenda : la DMIA est d'une demi-journée ; 4 h laissent ≈ 1 h de marge et couvrent ≈ 45 min de décision. Le RPO de 15 min est l'addition, dans le pire cas, de `archive_timeout` (5 min : un segment de WAL partiellement rempli n'est archivé qu'au plus 5 min après), de l'envoi vers `s3-01` (secondes), de `filer.sync` (secondes à 1 min, retard mesuré en S04) : ≈ 7 min, arrondi à 15 min avec marge. Il est 4 fois inférieur à la PDMA. Un RPO de quelques secondes exigerait la réplication en flux à travers `wg0` (S06, « pour aller plus loin ») : non retenu en v1 (exposition de la base de prod à un autre site, complexité).
- MédiDoc : 1 h de RPO est la fréquence de copie (15 min) plus la marge d'une copie en échec ; le RTO de 8 h tient dans la journée ouvrée.
- Legacy-RDV : RPO 24 h = la sauvegarde quotidienne existante ; le contester coûterait un flux continu MariaDB → PAR2 pour une application en fin de vie.
- MédiNotif : rien à protéger, tout se recalcule ; 8 h laissent partir le lot du soir.

**Ce qui n'est pas tenable avec `hp01`** (et ce qu'il faudrait) : un RTO de MédiAgenda inférieur à 1 h (il faudrait un site **chaud** : applications démarrées, base promue automatiquement, ≈ 16 Go de plus et un second hyperviseur à PAR2) ; la haute disponibilité à PAR2 (trois nœuds). Chiffrage d'ordre de grandeur dans l'ADR-0350.

## 4. Périmètre du PRA v1

Sont **exclus** du PRA v1, par décision écrite : MédiVisio, Data, la CI/CD, OpenStack, Backstage, l'observabilité **complète** (une supervision minimale de PAR2 est prévue) et l'identité (tableau ci-dessous).

| Élément | Dans le PRA v1 ? | Pourquoi |
|---|---|---|
| MédiAgenda, MédiDoc, Legacy-RDV, MédiNotif | **oui** | services aux patients et aux cabinets (BIA) |
| MédiVisio | **non** (v1) | 30 praticiens pilotes, aucun engagement contractuel de disponibilité, repli téléphonique simple ; mémoire de `hp01` déjà au plus juste. À réexaminer **dès** la signature d'un contrat de téléconsultation (condition inscrite dans l'ADR-0350) |
| Data (statistiques) | **non** | aucun usage clinique ; l'extraction pseudonymisée reprend après le retour à PAR1 (rattrapage d'une nuit) ; rien à protéger qui ne soit déjà dans la base de MédiAgenda |
| CI/CD, Harbor | **non** | gel des livraisons pendant le PRA ; correctif d'urgence possible par les miroirs de `adm02` et une image construite à la main, signée, poussée sur `reg02` (procédure d'exception de RB-350) |
| OpenStack, Backstage | **non** | pas de service aux patients |
| Observabilité | **minimale** | en permanence : sonde `ms-sonde-pra` sur `adm02` (noms globaux, toutes les 15 s) ; pendant un PRA (vague 6 de RB-350, ≈ 0,5 Go de plus pour `adm02`) : Prometheus mononœud, Alertmanager et Mailpit de secours sur `adm02` — disponibilité des noms globaux, santé et archivage de la base de PAR2, mémoire et disque de `hp01`, alertes reçues par la cellule ; pas de Loki, Tempo ni Grafana à PAR2 (mémoire) |
| Identité (Keycloak, FreeIPA) | **non** | accès à PAR2 par comptes de bris de glace et clés SSH de l'enveloppe ; patients non concernés |
| Coffre (OpenBao) | **oui, en secours** | `bao-par2` restauré depuis le dernier instantané (RPO ≤ 1 h), descellé par `kms01` restauré |

## 5. Ce qui déclenche, ce qui termine

- Déclenchement : critères et autorité dans RB-350 (S07) ; Claire Morel décide, Nadia Roussel la supplée.
- Fin du PRA : décision de retour (RB-351, S12) ; on ne revient pas tant que PAR1 n'a pas été reconstruit **et** vérifié.

# La TSDB de Prometheus sous le capot (témoin de mon01)

> Analyse PLAT-2244 du 27 octobre 2026, sur un instantané du Prometheus témoin 3.13.5 de `mon01` (rétention 30 jours, collecte toutes les 15 s). API d'administration ouverte de 08:31 à 09:20 (MR !41 et !42 de `plateforme/ansible`), seul appel : `snapshot`. Instantané `20261027T084512Z-6d2a1f0c9b3e4a17` copié sur `adm01` puis supprimé de `mon01` à 08:52. Les chiffres ci-dessous sont **ceux de cet exemple** : remplace-les par les tiens.

## Le WAL et la tête

Ce qu'on voit dans `/var/lib/prometheus/data` :

| Élément | Contenu | Relevé |
|---|---|---|
| `wal/00000413`, `00000414` | segments du journal d'écriture (128 Mio au plus) : séries créées, échantillons, *tombstones* | 2 segments, 21 Mio ; `prometheus_tsdb_wal_segment_current` = 414 |
| `wal/checkpoint.00000412` | état condensé des segments ≤ 412 : séries encore vivantes et échantillons postérieurs au dernier bloc | créé à 07:00, à la création du dernier bloc |
| `chunks_head/000003` | chunks **complets** de la tête, écrits sur disque et projetés en mémoire (*mmap*) | 6,2 Mio |
| la tête (mémoire) | séries actives, index inversé, chunk ouvert de chaque série | `prometheus_tsdb_head_series` = 1 932 ; `prometheus_tsdb_head_chunks` = 5 811 ; de 07:00 à maintenant |
| `lock`, `queries.active` | verrou du répertoire ; requêtes en cours (relu au redémarrage pour journaliser celles qu'un plantage a interrompues) | — |

Chemin d'un échantillon : collecte → ajout à la tête (chunk ouvert de la série) **et** au WAL → quand le chunk atteint 120 échantillons (30 min à 15 s), il est fermé, compressé et écrit dans `chunks_head/` → quand la tête couvre 3 h (1,5 × la durée de bloc), les 2 h les plus anciennes deviennent un **bloc** persistant, et le WAL est tronqué (checkpoint).

## Les blocs

`promtool tsdb list -r` sur l'instantané (extrait) :

| ULID | Début | Fin | Durée | Séries | Échantillons | Taille |
|---|---|---|---|---|---|---|
| `01M5KZTAER58G4VTX2P5BBXAJZ` | 20/10 10:02 | 22/10 06:00 | 43 h 58 | 1 913 | 9 204 518 | 13 Mio |
| `01M5RG0NMGREW6VNX9NP3GVBAE` | 22/10 06:00 | 24/10 06:00 | 48 h | 1 906 | 10 051 200 | 14 Mio |
| `01M5Y2H8RW60SFDSFHMSZH9F2A` | 27/10 05:00 | 27/10 07:00 | 2 h | 1 908 | 418 800 | 1,1 Mio |
| `01M5Y8HWMGAXSCN6G9N791C1WF` | 27/10 07:00 | 27/10 08:45 | 1 h 45 | 1 932 | 366 450 | 1,0 Mio |

Un bloc = un dossier nommé par un **ULID** (identifiant triable : les 10 premiers caractères codent l'heure de création en millisecondes) :
- `meta.json` : `minTime`, `maxTime` (ms), `stats` (séries, échantillons, chunks), `compaction.level` et `compaction.sources` (blocs d'origine) ;
- `index` : symboles (toutes les chaînes), séries (étiquettes + références de chunks), listes de *postings* (pour chaque paire étiquette=valeur, les séries qui la portent) ;
- `chunks/000001…` : les chunks compressés, regroupés en segments de 512 Mio au plus ;
- `tombstones` : intervalles supprimés (vide ici).

Le dernier bloc (1 h 45) n'existait pas : c'est la tête, écrite pour l'instantané. Décodage de l'ULID `01M5Y2H8RW…` : 1793084400412 ms, soit le 27/10 07:00:00 UTC, heure de création du bloc 05:00-07:00. Les blocs compactés sont alignés sur des multiples de leur durée : aux extrémités (premier jour, jours récents) ils sont plus courts que 54 h.

## La compaction et la rétention

- Les blocs de 2 h (niveau 1) sont fusionnés en blocs de 6 h (niveau 2), 18 h (niveau 3), 54 h (niveau 4) : progression × 3, plafonnée à 10 % de la rétention (30 j → 72 h ; 54 h est la dernière étape sous le plafond). `01M5RG…` : `compaction.level` 4, 8 sources.
- Dans le cluster, l'opérateur fixe la durée **minimale et maximale** des blocs à 2 h parce que le sidecar Thanos envoie les blocs tels quels : la compaction se fait une seule fois, dans le compartiment, par le Compactor (M21-E25).
- La rétention supprime des **blocs entiers** dont tout le contenu est trop vieux ; elle ne coupe jamais un bloc. Sur le témoin, le plus vieux bloc commence le 20/10 (installation) : rien n'est encore supprimé.

## Analyse et cardinalité

`promtool tsdb analyze --limit=5` sur `01M5RG…` : 1 906 séries, 61 noms d'étiquettes, 1 874 paires uniques. Métriques les plus nombreuses : `prometheus_http_request_duration_seconds_bucket` (88), `probe_http_duration_seconds` (60 : 5 phases × 12 cibles), `node_*` de `pve01` et `pbs01`. Étiquette la plus coûteuse : `le` (91 valeurs, histogrammes). Aucun *churn* notable (les séries du témoin sont stables).

`--extended` : 116 échantillons par chunk en moyenne (max 120) : compression proche de l'optimum ; quelques chunks à 1 échantillon (séries apparues ou disparues dans le bloc).

`promtool tsdb dump --match='probe_success{instance="https://grafana.apps.par1.medisphere.internal/api/health"}'` sur une heure : 240 lignes → un échantillon toutes les 15 s. (`promtool tsdb dump` exige un dossier `wal/` dans le répertoire analysé : créé vide dans la copie.)

Coût d'une série sur le témoin : 14 Mio pour 1 906 séries sur 48 h ≈ 7,5 Kio par série et par 48 h, soit ≈ 1,3 octet par échantillon ; en mémoire, la mesure fiable est celle du cluster (M21-E30). Les 200 000 séries de M21-E38 auraient pesé ≈ 100 fois le témoin entier.

## Réponses aux questions

1. **WAL** : rend durable la tête (en mémoire) ; au redémarrage, rejeu depuis le dernier checkpoint ; le checkpoint borne ce rejeu. Grosse tête = rejeu long (plusieurs minutes), pendant lequel Prometheus ne collecte pas.
2. **`chunks_head/`** (depuis 2.19) : chunks complets hors du tas, projetés en mémoire ; moins de mémoire résidente, et ces chunks n'ont pas à être reconstruits au rejeu.
3. **Immuabilité** : lecture sans verrou, liens physiques (instantanés), envoi tel quel au stockage objet. Suppression = *tombstones* ; l'espace est libéré à la réécriture du bloc (compaction ou `clean_tombstones`).
4. **Rétention** : par durée (blocs entièrement trop vieux) et par taille (blocs les plus anciens jusqu'à repasser sous la limite, WAL et `chunks_head` compris) ; granularité = un bloc.
5. **Thanos** : blocs de 2 h fixes (`min` = `max`) car le sidecar envoie ce que Prometheus écrit ; compacter localement réécrirait des blocs déjà envoyés. Le Compactor compacte et sous-échantillonne dans le compartiment, seul.
6. **Échantillons par chunk** : efficacité de compression ; fermeture à 120 échantillons (ou à la frontière de bloc) ; le *churn* laisse des chunks presque vides, chers.
7. **Coût d'une série** : voir la section précédente ; rapporté à M21-E38, 200 000 séries ≈ plusieurs centaines de Mo de tête par réplica, et un index de bloc multiplié d'autant.
8. **Instantané** : état figé et cohérent ; le répertoire vivant change sans cesse et est verrouillé ; `promtool` pourrait y rejouer le WAL et écrire.

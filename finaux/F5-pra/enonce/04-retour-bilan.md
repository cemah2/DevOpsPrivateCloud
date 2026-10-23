# Final F5 — Phase 4 : Retour et bilan

PAR2 a tenu. PAR1, lui, n'a jamais cessé de tourner : isolé, il a continué d'écrire dans sa base, d'archiver, de croire qu'il était la production. Revenir, ce n'est pas « rebrancher le câble » : c'est décider quelle version de la vérité gagne, rapatrier ce qui a été écrit à PAR2, et basculer une seconde fois, proprement cette fois, avec une coupure courte et annoncée. Ensuite viendra le rapport, puis ce qui fera de cet exercice une habitude plutôt qu'un exploit.

Prérequis de la phase : phase 3 terminée (`lab/bin/check F5 9` à `lab/bin/check F5 11` verts depuis `adm02`) ; décision de retour prise par Claire Morel et annoncée aux métiers.

> ⚠️ **Attention** : le premier geste du retour se fait **depuis `pve01`**, en sens inverse de toute la phase 3 : tu vas de nouveau toucher PAR1. Rien ne doit en sortir vers PAR2 (réplications, miroirs, DNS) avant qu'il ait été neutralisé. L'annulation du sinistre (`lab/bin/break F5 9 --annuler`) refuse de lever l'isolement tant que la base de PAR1 n'est pas neutralisée.

---

### F5-S12 — Le retour à PAR1  `LIBRE` `★★★★`

> **Fiche CHG-3512** — *De : Claire Morel* — *Copie : Nadia Roussel, Julien Petit, Karim Benali, Sophie Laurent*
> On rentre. Trois règles. Un : rien de ce que les cabinets ont écrit pendant le PRA ne se perd — rendez-vous, documents, et je veux la preuve. Deux : l'ancien PAR1 ne doit jamais, même une seconde, se croire la production quand le lien revient. Trois : la coupure de retour est courte, annoncée, et mesurée comme la première ; si elle dérape, on reste à PAR2 et on réessaie demain. Et je veux enfin le vrai RPO de l'exercice : PAR1 l'a gardé pour nous.

**Objectifs pédagogiques**
- Revenir d'un PRA sans perte : neutraliser l'ancien site, réconcilier les données divergentes, resynchroniser en sens inverse, basculer de façon contrôlée.
- Mettre en œuvre une bascule **contrôlée** en topologie distribuée CloudNativePG (rétrogradation et promotion par jetons), après une reconstruction de l'ancien primaire.
- Remettre chaque flux de réplication et chaque nom dans son sens de temps normal, dans le bon ordre.

**Prérequis** : F5-S09 à F5-S11 ; M16 et M27 (CloudNativePG, plugin Barman Cloud, `serverName`), M06 (PowerDNS : primaire, secondaire, numéro de série), F1-S11 (récupération sous un nouveau `serverName`), RB-350.
**Durée indicative** : 6 à 8 h, dont une fenêtre de coupure annoncée.

**Contexte technique**
- PAR1 a tourné isolé depuis T0 : `mediagenda-db` (PAR1) est resté primaire, a reçu des témoins (et peut-être d'autres écritures internes), a archivé vers `s3-01` sous `mediagenda-db-prod-day0`. Les deux bases ont **divergé** (deux lignes temporelles).
- Pendant le PRA, des écritures n'existent qu'à PAR2 : la base `mediagenda-db-par2` (archives dans `cnpg-k8s-par2` de `s3-02`), les documents MédiDoc déposés dans `medidoc-documents` de **`s3-02`**, la base de Legacy-RDV restaurée à PAR2, les commits poussés dans les miroirs de `adm02` (documentation, fichiers de site), l'état DNS de dns03 (zones passées en natif, CNAME vers PAR2, numéro de série plus élevé que celui de dns01).
- Les flux de temps normal reprendraient seuls au rétablissement du lien : `filer.sync` (`s3-01` → `s3-02`), la minuterie `rclone` (RGW → `s3-02`, qui **synchronise**), les *push mirrors* de GitLab vers `adm02`, les transferts de zone de dns01 vers dns03.
- Isolement : levé par `root@pve01:~/DevOpsPrivateCloud# lab/bin/break F5 9 --annuler` ; refus tant que le `Cluster` `mediagenda-db` de `mediagenda-prod` n'est pas clôturé (*fenced*), en réplique, ou absent (lecture par le compte des checks de `adm01`). L'annulation retire, sur chaque passerelle, la table `inet f5_sinistre`, son garde (`f5-sinistre-garde.timer`, qui la reposait après un rechargement du pare-feu) et le complément `nftables.service.d/f5-sinistre.conf`. T0 et l'heure de levée restent dans `/var/lib/workbook/` de `gw01`.
- ⚠️ **Secours** (seulement si l'annulation échoue, ou pour une urgence réelle du lab, notée dans la main courante) : depuis la console Proxmox de chaque passerelle (`qm terminal`, ou l'interface de `pve01`), en root : `rm -f /var/lib/workbook/f5-sinistre.nft` (désarme le garde), `systemctl disable --now f5-sinistre-garde.timer`, `nft delete table inet f5_sinistre` ; sur `gw01` seulement, note l'heure de levée : `printf 'LEVEE_EPOCH=%s\n' "$(date +%s)" > /var/lib/workbook/f5-levee`. Relance ensuite l'annulation normale (idempotente) pour retirer le reste et effacer le marqueur de `adm01`.
- CloudNativePG 1.30, topologie distribuée : rétrogradation (`spec.replica.primary` changé sur le primaire, jeton dans `.status.demotionToken`), promotion (`primary` et `promotionToken` dans la **même** modification) : <https://cloudnative-pg.io/docs/1.30/replica_cluster>.
- Preuves attendues par le check dans `docs/pra/mesures/2026-exercice-1/` : `temoins-par2.csv` (`id,cree_le,motif` des témoins écrits à PAR2 pendant le PRA) et `medidoc-par2.csv` (identifiants des documents déposés à PAR2 pendant le PRA, un par ligne en première colonne) ; runbook `docs/pra/runbooks/RB-351-retour-par1.md` ; fiche `docs/pra/exercices/2026-exercice-1/CHG-3512-retour-par1.md`.
- Coupure de retour : mesurée par `ms-sonde-pra` (adm02) ; le check accepte au plus `WB_F5_COUPURE_RETOUR_MAX_MIN` minutes (15 par défaut) d'échecs consécutifs sur MédiAgenda après la levée de l'isolement.

**Travail demandé**

Objectifs :
1. **Préparer** : RB-351 et CHG-3512 (fenêtre, ordre, critères de passage, coupure visée, retour arrière à chaque étape — y compris « rester à PAR2 ») relus et validés **avant** de toucher PAR1.
2. **Neutraliser PAR1** depuis `pve01`, isolement toujours en place : plus aucune écriture ni archivage par l'ancien primaire, données divergentes **conservées** et exportées pour la réconciliation, aucun flux de temps normal qui puisse écraser PAR2 au rétablissement du lien. Faire constater par Sophie, puis lever l'isolement.
3. **Resynchroniser PAR2 → PAR1** pendant que PAR2 sert les patients : la base (PAR1 reconstruit comme réplique de PAR2), les documents MédiDoc, la base de Legacy-RDV, les commits des miroirs vers GitLab, l'état DNS.
4. **Basculer** par jetons CloudNativePG, dans une coupure courte annoncée : PAR2 rétrogradé, PAR1 promu, noms globaux revenus à PAR1, dns03 redevenu secondaire au même numéro de série que dns01.
5. **Revenir en veille** : `mediagenda-db-par2` réplique de PAR1, témoin et applications de PAR2 à l'arrêt, réplications de temps normal relancées dans le bon sens, INC-6109 clos.
6. **Établir le vrai RPO** à partir de ce que PAR1 avait gardé, et la liste de ce qui a été écrit à PAR1 entre le dernier WAL arrivé à PAR2 et T0 (ce qu'un vrai sinistre aurait perdu) : décision écrite de ce qu'on en fait, avec Julien.

Contraintes :
- Aucune donnée détruite à PAR1 avant d'avoir été exportée et sauvegardée (instantané des volumes de l'ancien primaire conservé jusqu'à la clôture du rapport).
- Aucun flux PAR1 → PAR2 (objets, miroirs, zones) n'est rétabli avant d'avoir vérifié qu'il ne supprime ni n'écrase rien de ce qui a été écrit pendant le PRA.
- La bascule de la base se fait par jetons (aucune promotion de PAR1 sans le jeton de rétrogradation de PAR2).
- Pas de données de patients dans Git : les exports qui en contiennent vont à Julien par un canal chiffré ; seuls les témoins et des identifiants de documents vont dans `docs/pra/mesures/`.

**Critères de réussite**
- [ ] La table `f5_sinistre` et son garde n'existent plus sur `gw01` ni `gw02`.
- [ ] dns01 et dns03 publient les trois noms globaux vers `*.apps.par1.medisphere.internal` ; la zone `medisphere.internal` est secondaire sur dns03, au même numéro de série que dns01 ; les trois noms répondent en 2xx avec `X-MediSphere-Site: par1`.
- [ ] `mediagenda-db` (PAR1) est primaire, sain, non clôturé, archive ses WAL, et a été créé après T0 ; `mediagenda-db-par2` est de nouveau sa réplique, saine et à jour.
- [ ] `temoin-rpo` est actif à PAR1 et suspendu à PAR2 ; `filer.sync` tourne de nouveau sur `s3-02`.
- [ ] Chaque témoin de `temoins-par2.csv` et chaque document de `medidoc-par2.csv` est servi par PAR1.
- [ ] La coupure du retour mesurée par la sonde est sous l'objectif ; RB-351 et CHG-3512 sont publiés ; INC-6109 est clos dans la main courante sur `main`.

**Vérification** : `lab/bin/check F5 12` (depuis `adm01`)

<details><summary>Indice 1</summary>

Liste chaque flux de réplication de temps normal (objets, documents, code, zones, base) et pose deux questions : « que fait-il à la seconde où le lien revient ? » et « dans quel sens doit-il couler pendant le retour ? ». Un flux de synchronisation (copie **et** suppression) vers PAR2 est le plus dangereux : il efface tout ce qui n'existe pas à la source.
</details>

<details><summary>Indice 2</summary>

Un ancien primaire qui a divergé ne redevient pas réplique : il se reconstruit. Avant de le détruire, il a deux choses à donner — ses écritures postérieures au dernier WAL arrivé à PAR2 (le vrai RPO, et ce qu'un vrai sinistre aurait perdu), et une copie de sécurité. Pour sa reconstruction, relis F1-S11 : on ne réécrit jamais sous un `serverName` qui contient déjà une autre histoire.
</details>

<details><summary>Indice 3</summary>

Un secondaire PowerDNS n'accepte un transfert que si le numéro de série du primaire est **plus grand** que le sien. Pendant le PRA, dns03 a incrémenté le sien ; dns01 n'a pas bougé. Et pour la base : le jeton de rétrogradation n'apparaît qu'une fois que le primaire rétrogradé a archivé son dernier segment ; la promotion attend que le promu ait rejoué jusqu'à ce point — lequel doit donc pouvoir lire l'archive de l'autre.
</details>

**Pour aller plus loin** (facultatif) : chronométrer chaque étape du retour et en tirer un « RTO de retour » ; automatiser la neutralisation de PAR1 (un script lancé depuis `pve01` qui refuse de rendre la main tant que les cinq conditions ne sont pas vraies).

---

### F5-S13 — Le rapport d'exercice PRA  `RED` `★★`

> **Ticket PLAT-3513** — *De : Claire Morel* — *Copie : direction, Sophie Laurent, Nadia Roussel, Julien Petit, Karim Benali*
> La direction attend un rapport, l'auditeur HDS aussi. Deux pages pour la direction en tête : a-t-on tenu nos objectifs, oui ou non, et combien ça a coûté aux patients. Ensuite le détail, chiffres de Sophie à l'appui. Aucune phrase du genre « globalement bien passé » : des heures, des écarts, des causes, des actions avec un nom et une date.

**Objectifs pédagogiques**
- Rendre compte d'un exercice de PRA de façon factuelle, vérifiable et sans recherche de coupable.
- Confronter les objectifs (S01) aux mesures, expliquer chaque écart et en tirer des actions.
- Réviser le PRA à partir de ce qu'on a appris (objectifs, runbooks, architecture).

**Prérequis** : F5-S12.
**Durée indicative** : 3 h.

**Contexte technique**
- Sources : main courante (`docs/pra/journal/`), relevés de Sophie, mesures de la sonde, comptes rendus de S08 et S11, RB-350 et RB-351 annotés, fiche CHG-3512.
- Le check lit l'en-tête YAML de `docs/pra/exercices/2026-exercice-1/rapport.md` (clés `t0`, `rto-mediagenda-min`, `rto-medidoc-min`, `rto-rdv-min`, `rpo-mediagenda-min`, `coupure-retour-min`) et recalcule les RTO à partir de **`docs/pra/mesures/2026-exercice-1/sonde-mesures.csv`** (copie des mesures de `ms-sonde-pra` couvrant l'exercice) : à 2 minutes près, les deux doivent concorder.
- Actions issues du rapport : tickets **PLAT-3530** et suivants.

**Travail demandé**
1. Exporte les mesures de la sonde couvrant l'exercice dans `docs/pra/mesures/2026-exercice-1/sonde-mesures.csv`.
2. Rédige `docs/pra/exercices/2026-exercice-1/rapport.md` : synthèse pour la direction (objectifs tenus ou non, effet sur les patients) ; tableau objectifs contre mesures (RTO par application, RPO de MédiAgenda — la valeur **exacte** établie en S12 —, RPO des autres, coupure du retour, durée de décision) ; chronologie de T0 à la clôture ; écarts au runbook et incidents (INC-6108, INC-6110), avec leurs causes ; ce qui a bien marché ; actions (PLAT-3530+, responsable, échéance) ; révisions décidées (objectifs, RB-350, RB-351, ADR-0350).
3. Mets à jour les documents que le rapport déclare faux (au moins `objectifs.md` et RB-350), par MR liée.

**Critères de réussite**
- [ ] `rapport.md` est sur `main` avec son en-tête de mesures complet, les objectifs, la chronologie, les écarts, les leçons et des actions PLAT-35xx.
- [ ] Les RTO déclarés concordent (± 2 min) avec ceux que l'on recalcule sur `sonde-mesures.csv`.

**Vérification** : `lab/bin/check F5 13` (présence, en-tête, cohérence avec les mesures ; la qualité de l'analyse se juge avec le corrigé).

<details><summary>Indice 1</summary>

Sépare trois durées que la direction confond : T0 → décision (organisation), décision → reprise (technique), reprise → service complet (mode dégradé). Chaque écart s'explique dans l'une d'elles.
</details>

<details><summary>Indice 2</summary>

Un écart n'est pas une faute : c'est la différence entre ce qui était écrit et ce qui s'est passé. Sa cause est un mécanisme (un runbook muet, une dépendance oubliée, une configuration de site), son action une modification vérifiable (un contrôle, une alerte, une ligne de runbook).
</details>

**Pour aller plus loin** (facultatif) : une version « une page » pour l'auditeur HDS (mesure 5.30 de l'ISO 27001:2022, continuité des TIC) avec les preuves référencées.

---

### F5-S14 — Recette `pra-v1` : une reprise qui se teste  `LIBRE` `★★★`

> **Ticket PLAT-3514** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel*
> Un exercice par an, c'est bien ; savoir chaque semaine qu'on pourrait reprendre, c'est mieux. Je veux trois choses avant de poser `pra-v1`. Que PAR2 nous dise lui-même quand il n'est plus prêt : retard de réplication, témoin trop vieux. Qu'un test de reprise, partiel mais réel, tourne tout seul chaque trimestre, et qu'il échoue bruyamment. Et un calendrier : qui teste quoi, quand, jusqu'au prochain exercice complet. La documentation doit permettre à quelqu'un qui n'était pas là de tout refaire.

**Objectifs pédagogiques**
- Faire de la capacité de reprise un état **mesuré en continu** et alerté, et non une conviction.
- Automatiser un test de reprise partiel reproductible, avec des seuils et une sortie exploitable.
- Planifier les tests (partiels, répétitions, exercice annuel) et clore un final par une recette.

**Prérequis** : F5-S08 (contrôle de préparation), F5-S11 (supervision de PAR2), F5-S13 ; M19 (pipelines planifiés, runner protégé), M21 (règles d'alerte).
**Durée indicative** : 6 à 8 h.

**Contexte technique**
- Le check lit les règles et une métrique du **Prometheus de PAR2** (`WB_F5_PROM_PAR2_URL`) : une alerte dont l'expression porte sur l'âge du témoin à PAR2 (métrique dont le nom contient **`pra_temoin_age_secondes`**) et une sur le retard de réplication (`cnpg_pg_replication_lag`) ; la métrique d'âge doit exister et rester sous 15 min.
- Le test trimestriel est attendu sous la forme d'un **pipeline planifié** actif de `plateforme/k8s` (variable `WB_F5_PROJET_ESSAI` pour un autre projet) dont la description contient « pra » ou « reprise », et dont le dernier pipeline a réussi. Le runner protégé joint `k8s-par2` à travers `wg0` (flux à ouvrir et à écrire dans la matrice).
- `k8s-par2` n'a qu'un nœud de 5 Go : un test qui restaure la base y tient-il en veille, et combien de temps ?
- Documentation attendue sur `main` : `bia.md`, `objectifs.md`, `dependances.md`, `adr/ADR-0350-…`, `enveloppe.md`, `cellule-de-crise.md`, `runbooks/RB-350-…`, `runbooks/RB-351-…`, `exercices/2026-exercice-1/rapport.md`, `calendrier-tests.md`.
- Étiquette finale **`pra-v1`** sur `plateforme/medisphere`.

**Travail demandé**

Objectifs :
1. **Alertes de préparation** à PAR2 : retard de la réplique de PAR2, âge du dernier témoin vu à PAR2, et l'indicateur du contrôle de préparation (S08) ; chacune essayée (provoquée puis résolue) et routée vers quelqu'un en temps normal.
2. **Test de reprise trimestriel automatisé** : chaque trimestre, sans intervention, restaurer la base de production à PAR2 depuis l'archive de `s3-02` dans un espace jetable, mesurer la durée et l'âge des données restaurées, vérifier quelques invariants (témoin, nombre de lignes, images présentes sur `reg02`, DNS de PAR2), tout nettoyer, et échouer si un seuil est dépassé ; un premier passage réussi.
3. **Calendrier** `docs/pra/calendrier-tests.md` : tests automatiques, répétitions à blanc, exercice annuel (date 2027), revue de l'enveloppe, revue des objectifs ; qui, quand, critère de réussite, où va le résultat.
4. **Documentation complète** : un index de `docs/pra/`, documents à jour après le rapport, procédures relues par quelqu'un qui n'a pas fait l'exercice.
5. Pose **`pra-v1`** quand tout est sur `main` et que les contrôles de F5 sont verts.

Contraintes :
- Le test ne touche jamais la base de veille `mediagenda-db-par2` ni la production de PAR1 ; il tient dans la mémoire de `k8s-par2-n01` et rend tout ce qu'il a pris.
- Aucun secret dans le dépôt : identifiants du test dans les variables protégées de la CI.
- PAR2 est revenu en veille (aucune application de PAR2 en marche, témoin suspendu à PAR2).

**Critères de réussite**
- [ ] Le Prometheus de PAR2 porte une alerte sur l'âge du témoin et une sur `cnpg_pg_replication_lag` ; la métrique d'âge du témoin existe et vaut moins de 15 min.
- [ ] Un pipeline planifié actif de test de reprise existe et son dernier pipeline a réussi.
- [ ] Toute la documentation listée est sur `main`, dont `calendrier-tests.md` (tests trimestriels, exercice annuel 2027, responsables).
- [ ] PAR2 est en veille : aucun pod de l'API de MédiAgenda en marche à PAR2, `temoin-rpo` suspendu à PAR2.
- [ ] L'étiquette `pra-v1` est posée sur `plateforme/medisphere`.

**Vérification** : `lab/bin/check F5 14`

<details><summary>Indice 1</summary>

L'âge du témoin est une requête SQL ; CloudNativePG sait exposer le résultat d'une requête comme une métrique de l'exportateur de chaque instance (requêtes de supervision personnalisées), y compris sur une réplique. Le Prometheus de PAR2 de S11 lit déjà cet exportateur.
</details>

<details><summary>Indice 2</summary>

Un test de reprise utile **échoue** quand il le faut : choisis les seuils avant d'écrire le script (durée maximale de restauration, âge maximal des données, nombre minimal de rendez-vous), et provoque un échec une fois pour voir qui est prévenu et comment.
</details>

**Pour aller plus loin** (facultatif) : un test mensuel plus léger (contrôle de préparation + `git ls-remote` des miroirs + signature d'une image de `reg02`) ; un tableau de bord « capacité de reprise » (RPO courant, dernier test réussi, prochaine échéance).

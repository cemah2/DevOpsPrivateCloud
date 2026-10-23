# RB-350 — Bascule sur PAR2 (sinistre de PAR1)

| | |
|---|---|
| Ticket | PLAT-3507 |
| Déclenche | Claire Morel (suppléante : Nadia Roussel) |
| Pilote | Nadia Roussel (cellule de crise, `cellule-de-crise.md`) |
| Exécutants | deux personnes de l'équipe Plateforme : **A** (clavier) et **B** (lit le runbook à voix haute, coche, tient l'heure) |
| Observatrice | Sophie Laurent : relève heures et preuves, n'agit pas |
| Durée de référence | ≈ 2 h 30 de la décision à la reprise de MédiAgenda (répétition S08) ; RTO de MédiAgenda : **4 h** depuis T0 |
| Retour | RB-351 |
| Version | <AAAA-MM-JJ> — imprimée dans l'enveloppe (E12) |

> Chaque étape se termine par une **preuve** : la sortie de la commande de contrôle, collée dans la main courante (`docs/pra/journal/<AAAA-MM-JJ>.md` sur `adm02`, une ligne `- HH:MM INC-6109 [type] texte`). Une condition de passage non remplie = on **s'arrête**, on le dit à la cellule, on applique « Si une vague échoue » (§ fin).

## Déclenchement

**Critère** (on ne le discute pas à chaud) : PAR1 **injoignable** depuis PAR2 **et** depuis l'extérieur (ton poste par Internet, un cabinet) depuis **30 min**, **et** l'équipe sur place (ou l'hébergeur) annonce un retour **au-delà de 2 h** ou ne peut rien annoncer. Calcul : RTO 4 h − 2 h 30 de bascule − marge de 30 min ⇒ décision au plus tard à **T0 + 1 h**.

**Autorité** : Claire décide (Nadia si Claire est injoignable 15 min). La décision est écrite : `- HH:MM INC-6109 [décision] déclenchement du PRA (critère : …)`.

**On ne déclenche pas** pour une panne partielle de PAR1 qui a un correctif dans l'heure (astreinte, F3), ni pendant qu'une intervention en cours à PAR1 peut aboutir.

## Préalables (vérifiables, 10 min)

- [ ] Accès : VPN `wg1` de `hp01` (E8) depuis ton poste ; `ssh admin@10.20.20.10` (`adm02`).
- [ ] Enveloppe ouverte (E1, E2, E4, E6, E7, E9) ; trois gardiens de parts joignables.
- [ ] `hp01` sain : PBS actif, mémoire libre ≥ 4 Go (`free -g`), aucune tâche PBS lourde (vérification, GC) : si oui, l'**arrêter** (`proxmox-backup-manager task stop <UPID>`) : la mémoire va au PRA.
- [ ] Heure : `chronyc tracking` sur `hp01` synchronisé (sources hors PAR1).
- [ ] Main courante ouverte sur `adm02` (`docs/pra/journal/<date>.md` du miroir de `plateforme/medisphere`) ; heure **T0** notée (première indisponibilité constatée ; exercice : `/var/lib/workbook/f5-t0` de `adm02`, connue de Sophie).

## Vague 0 — Isoler et figer (15 min)

1. **PAR1 ne doit plus écrire.** Si PAR1 est vivant mais isolé (coupure réseau), il continue d'accepter des rendez-vous de ceux qui le joignent encore : demander à l'équipe sur place (ou à l'hébergeur) de **couper son accès public** ou de l'arrêter. Si personne ne peut le confirmer, on bascule quand même et on traite la divergence au retour (RB-351 : l'ancien primaire est reconstruit, ses écritures postérieures à T0 sont exportées et réconciliées).
2. Arrêter les réplications entrantes (RB-354 §4) : `systemctl stop 'seaweedfs-filer-sync@*' medidoc-copie.timer` sur `s3-02`.
3. Relever l'âge des dernières données (`/var/lib/prometheus/node-exporter/pra_replication.prom` sur `s3-02`) → main courante `[mesure]`.

**Condition de passage** : `ping -c3 10.10.20.10` depuis `adm02` en échec ; décision de Claire tracée ; âges relevés.

## Vague 1 — Socle de PAR2 (20 min)

1. `dns03` devient **primaire** des zones internes : sur `dns03`, chaque zone passe de « secondary » à « native » (`pdnsutil` de PowerDNS 5 : sous-commande de changement de type de zone, voir `pdnsutil --help` de ta version), API locale activée (variables `powerdns_auth_mode: primaire`, `powerdns_auth_api_active: true` dans `host_vars/dns03/`, playbook depuis `adm02`).
2. `adm02` devient la **forge** : compte `admin` autorisé en écriture sur `/srv/miroirs` le temps du PRA ; toute modification du PRA est commitée là (message `PRA INC-6109 : …`).
3. Sonde `ms-sonde-pra` (minuterie de 15 s sur `adm02`) active ; `tail -f /var/lib/ms-sonde-pra/mesures.csv`. (Le reste de la supervision minimale vient en vague 6.)

**Condition de passage** : `dig @10.20.20.11 SOA medisphere.internal` répond ; `pdnsutil list-all-zones` de `dns03` montre les zones en `native` ; la sonde écrit (échecs attendus).

## Vague 2 — Secrets (45 min)

RB-355 §2 à §5 **et** §7 (en PRA) : `kms01` restauré en 3501 (10.20.20.24, isolé), descellé par trois parts ; `bao-par2` démarré, initialisé, instantané le plus récent restauré, redémarré : descellé par transit.

Puis :
1. Moteur `db-mediagenda` repointé vers `10.20.20.205:5432` (RB-356 §4) — après la vague 3 si la base n'est pas encore promue (il ne peut pas créer d'utilisateurs sur un réplica).
2. `SecretStore` de `k8s-par2` repointés vers `https://bao-par2.par2.medisphere.internal:8200` (paramètre de l'Application, RB-356 §4) ; resynchronisation forcée des ExternalSecrets.

**Condition de passage** : `bao status` (`bao-par2`) : `Sealed false` ; âge de l'instantané restauré noté (RPO du coffre) ; ExternalSecrets statiques `Ready`.

## Vague 3 — Données (30 min ; + 1 h pour Legacy-RDV)

1. ⚠️ **POINT DE NON-RETOUR** : promotion de `mediagenda-db-par2`. PAR1 perdu : **sans jeton** (`spec.replica.primary: mediagenda-db-par2`, `kubectl apply --server-side` du fichier de site modifié **et commité sur le miroir**). À partir d'ici, deux primaires peuvent exister si PAR1 revient : le retour passe **obligatoirement** par RB-351 (l'ancien primaire reconstruit). Si PAR1 est vivant et joignable (sinistre partiel, exercice planifié) : bascule **avec jeton** (RB-356 §5).
2. Attendre `kubectl cnpg status mediagenda-db-par2` : primaire, nouvelle *timeline*, archivage vers `cnpg-k8s-par2` ; lancer une sauvegarde de base (`kubectl cnpg backup mediagenda-db-par2`).
3. **RPO** : requête du témoin (RB-356 §6) sur `mediagenda-db-par2` → `[mesure] dernier témoin à PAR2 : …`.
4. Repointage du moteur `db-mediagenda` (vague 2, étape 1) maintenant possible ; identifiants dynamiques reçus (`mediagenda-db-api` mis à jour).
5. Legacy-RDV (après MédiAgenda, RTO 8 h) : restauration de la dernière sauvegarde `mariadb-legacy-rdv/prod/` (mariadb-operator, `Restore` depuis l'identité `restauration-par2`) et des pièces jointes (Velero en lecture sur `velero-k8s-par1`, classe `cephfs` → `local-path`).

**Condition de passage** : primaire de PAR2 en écriture (`SELECT pg_is_in_recovery()` = `f`) ; RPO relevé ; sauvegarde de base lancée.

## Vague 4 — Applications (30 min)

Dans l'ordre de la BIA : **MédiAgenda**, puis MédiNotif, MédiDoc, Legacy-RDV.
1. MédiAgenda : réplicas de l'API à 1 et Valkey à 1 (paramètre de l'Application `mediagenda-prod` de `k8s-par2` ou commit sur le miroir) ; synchronisation manuelle (`argocd app sync mediagenda-prod`) : migrations (Flyway, sans effet attendu), API.
2. Contrôle direct : `curl -s https://mediagenda.apps.par2.medisphere.internal/pret` → 200 ; création d'un rendez-vous d'essai (praticien `PRA-ESSAI`), puis annulation.
3. MédiNotif : RabbitMQ (un nœud, définitions en code), worker ; **rejeu** des rappels du jour depuis MédiAgenda (procédure de Julien).
4. MédiDoc (`medidoc-recette`), puis Legacy-RDV : même schéma.

**Condition de passage** : `/pret` 200 sur `….apps.par2…` pour MédiAgenda ; création directe réussie.

## Vague 5 — Noms (10 min + TTL)

1. Sur `dns03` (primaire) : `mediagenda`, `medidoc`, `rdv` `.medisphere.internal` → CNAME vers `mediagenda.apps.par2.medisphere.internal`, `medidoc-recette.apps.par2…`, `legacy-rdv.apps.par2…` (API locale ou `pdnsutil`), TTL 60 s ; vidage du cache du récurseur (`rec_control wipe-cache medisphere.internal$`).
2. Attendre ≥ 60 s (TTL).
3. **T reprise** : première ligne de `mesures.csv` de la sonde avec création réussie par le nom global et `site=par2` ; confirmation de Julien depuis un poste extérieur. → `- HH:MM INC-6109 [mesure] REPRISE MédiAgenda (RTO = T reprise − T0 = …)`.

**Condition de passage** : RTO noté, confirmé par Julien, relevé par Sophie.

## Vague 6 — Mode dégradé

- Messages : cabinets (bandeau, message vocal, courriel aux 20 plus gros), direction (toutes les 2 h), autorités si données perdues (Sophie, DPO).
- Supervision minimale de PAR2 mise en service sur `adm02` (`objectifs.md` §4) : Prometheus, Alertmanager, Mailpit de secours ; alertes sur les noms globaux, la base de PAR2 (santé, archivage), la mémoire et le disque de `hp01` ; une alerte essayée jusqu'à la boîte de la cellule.
- En attendant, et en complément, surveillance par vacations (toutes les heures) : sonde, `kubectl get pods -A`, mémoire de `hp01`, espace de `s3-02` et de `par2-vms`, retard de sauvegarde de `mediagenda-db-par2`.
- Ce qui reste coupé : `objectifs.md` §3 (mode dégradé), livraisons gelées (exception : correctif d'urgence, annexe).

## Si une vague échoue

1. Le dire à la cellule (`[état]`), noter l'heure.
2. Ne **jamais** sauter une condition de passage pour « gagner du temps » : on a un RTO, pas une course.
3. Chercher 20 min avec le runbook de la brique (RB-353 à RB-356) ; au-delà, décision de Nadia : continuer, contourner (ex. MédiAgenda sans identifiants dynamiques : Secret statique de bris de glace créé à la main sur `k8s-par2`, mot de passe changé au retour), ou attendre.
4. Toute improvisation est écrite (`[décision]`), puis versée au rapport (S13).

## Annexe — PRA long (au-delà de 7 jours)

- Jeton de seal de `bao-par2` : RB-355 §5 (≈ 7 jours après la sauvegarde de `kms01`).
- Certificats ACME des VMs de PAR2 (15 jours au plus) : certificats émis par l'autorité de PAR2 (cert-manager, `Certificate` dans `k8s-par2`, exportés vers les VMs).
- DNSSEC de `par1` (≈ 2 semaines) : ancre retirée des récurseurs de PAR2.
- Sauvegarde hors de `hp01` : export quotidien de la base de PAR2 (`pg_dump` chiffré `age`) vers un support externe.
- Correctif d'urgence : construction d'image sur `adm02` (Podman), signature avec la clé de bris de glace (la clé `transit/cosign-medisphere` est dans `bao-par2`), poussée sur `reg02`, commit sur le miroir.

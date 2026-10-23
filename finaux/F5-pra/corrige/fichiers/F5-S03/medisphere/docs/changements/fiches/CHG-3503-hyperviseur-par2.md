---
chg: CHG-3503
titre: Proxmox VE à côté de PBS sur hp01 ; réseau et socle de PAR2
categorie: normal
statut: clos
decision: go
domaine: sauvegarde-par2
fenetre-debut: 2026-11-10T14:00:00+01:00
fenetre-fin: 2026-11-10T17:00:00+01:00
approbateurs: [claire.morel, sophie.laurent]
mesure-source: temoin
mesure-groupes: "continuite-.*"
mesure-debut: 2026-11-10T14:00:00+01:00
mesure-fin: 2026-11-10T17:00:00+01:00
mesure-objectif-s: 0
mesure-interruption-s: 0
---

# CHG-3503 — Proxmox VE à côté de PBS sur `hp01`

> Modèle de fiche du F4 (`docs/changements/fiches/modele.md`). Si F4 n'a pas été fait, les mêmes rubriques suffisent ; l'en-tête sert à la revue des changements.

## Risque et impact

- **Risque principal** : rendre PBS indisponible ou incohérent (paquets, noyau, réseau). Impact : **plus aucune sauvegarde** du lab tant que ce n'est pas réparé ; restauration impossible.
- Impact attendu pour les utilisateurs : **nul** (aucun service de production à PAR2) ; la mesure de continuité (sonde du F4) doit rester à 0 s.
- Exposition : changement unique, non répété → catégorie **normal**, approbation de Claire et de Sophie (sauvegardes = données de santé).

## Fenêtre

Mardi 14 h-17 h : après la vérification matinale de PBS, loin des sauvegardes de la nuit (20 h et suivantes). Contrôle du lendemain 8 h (sauvegarde nocturne).

## Préparation

- RB-353 relu à voix haute avec Karim (J−2).
- Accès de secours vérifié : iLO, SSH par le LAN (RB-353 §0).
- Aucune panne active, aucune tâche PBS en cours.

## Étapes

RB-353 §1 à §7, dans l'ordre. Points d'arrêt : fin de §1 (go/no-go), fin de §3 (contrôles PBS), fin de §6 (réseau).

## Critères de go/no-go

Sortie de `go-no-go-hp01.sh` : **GO** (jointe ci-dessous, avec `simulation-apt-<date>.txt`). Plus : *verify* de `ds-lab` vert, restauration d'un fichier d'essai réussie.

Critères d'**abandon** : un contrôle du §3 rouge ; PBS injoignable plus de 5 min ; toute modification non prévue de `vmbr0`, `vmbr1`, `wg0`.

## Retour arrière

RB-353 §6 (réseau) et §8 (désinstallation par l'historique d'APT). Limite écrite : non documenté par Proxmox ; dernier recours = réinstallation de PBS et import du datastore intact.

## Communication

Annonce à l'équipe (canal plateforme) au début et à la fin ; Nadia informée (aucun impact support attendu).

## Mesure

Sonde de continuité sur les groupes `continuite-*` (témoin de `mon01`) : objectif 0 s, relevé 0 s. Côté PBS : sauvegarde nocturne J+1 complète (nombre d'instantanés identique à J−1).

## Journal

- 14:02 go/no-go : GO (sortie jointe).
- 14:10 archive `pbs-config-20261110.tar.gz` copiée sur `adm01`, empreinte vérifiée.
- 14:18 installation lancée ; 14:31 terminée ; aucun paquet retiré (historique d'APT).
- 14:35 contrôles PBS et PVE verts ; dépôt d'entreprise désactivé.
- 15:20 stockage, pool, `vmbr2`, `inet par2`, `wg1` (rôle `hote_par2`) ; contrôles RB-353 §6 verts.
- 16:40 `adm02`, `dns03`, `s3-02` ; état migré sur `s3-02` ; `tofu plan` vide depuis `adm02`.
- J+1 08:05 sauvegarde nocturne complète.

## Clôture

Statut **clos** le <AAAA-MM-JJ> ; revue après mise en œuvre : aucun écart ; action : vérifier PBS **après chaque mise à jour** de Proxmox VE sur `hp01` (les deux produits partagent des bibliothèques) — ajouté à RB-353.

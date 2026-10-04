# Post-mortem — INC-2850 — Outillage d'exploitation hors service (contrôle des sauvegardes et `medictl`)

> Exemple de corrigé M02-E43, pour la paire M02-E35 variante 1 + M02-E36 variante 2. Heures
> fictives. À ranger dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-2850.md` de `plateforme/medisphere`.

| | |
|---|---|
| **Statut** | Relu |
| **Date de l'incident** | AAAA-MM-JJ (lundi) |
| **Rédacteur** | <apprenant>, astreinte Plateforme |
| **Relecteurs** | Nadia Roussel, Karim Benali, Sophie Laurent (droits et jetons) |
| **Sévérité** | P2 : aucune interruption de service utilisateur ; perte de la capacité de **vérifier** les sauvegardes et d'outiller les interventions (instantanés, inventaire) pendant une matinée |
| **Durée d'impact** | dimanche 18:05 → lundi 10:12 (16 h 07) pour `medictl` et `ms-snapshot` ; contrôle des sauvegardes manqué lundi 07:30, rétabli à 10:15 |
| **Services touchés** | `ms-verif-sauvegardes` (timer de `adm01`), `medictl`, `ms-snapshot` ; aucune VM, aucune sauvegarde |

## 1. Résumé

Lundi à 07:30, le contrôle quotidien des sauvegardes de `adm01` a échoué et `medictl` ne listait
plus aucune VM. Deux changements indépendants, faits la veille, se sont cumulés : un drop-in de
durcissement systemd (`ProtectHome=yes`) rendait le dossier de configuration du contrôle
invisible pour le service, et l'ACL de l'utilisateur Proxmox `wb-automation@pve` sur `/pool/lab`
avait été retirée lors d'un nettoyage des droits, ce qui privait ses deux jetons (`!lab` et
`!lecture`) de tout droit sur le pool. La seconde cause était masquée par la première pour le
contrôle des sauvegardes. Les deux ont été corrigées à 09:41 et 10:12. Les sauvegardes de la nuit
étaient complètes : aucune donnée en jeu.

## 2. Impact

- Contrôle des sauvegardes du lundi 07:30 manqué : pendant 2 h 45, personne ne savait si les
  sauvegardes de la nuit existaient (vérifiées a posteriori : toutes présentes, de moins de 6 h).
- `medictl vm list` renvoyait une liste vide (sans erreur) ; `ms-snapshot` refusait toute VM
  (« hors pool lab ») : l'intervention de 14 h sur `git01` aurait été faite sans instantané.
- Données : aucune perte ni exposition. Aucun secret n'a circulé pendant le diagnostic.
- Conformité : l'absence de contrôle pendant une matinée est consignée au registre HDS (le
  contrôle de résultat des sauvegardes fait partie des mesures déclarées).

## 3. Chronologie

| Heure | Événement | Source |
|---|---|---|
| Dim. 17:20 | Drop-in `20-durcissement.conf` (`ProtectHome=yes`, SEC-380) posé sur `ms-verif-sauvegardes.service` lors de la campagne de durcissement ; aucun lancement de test | `systemctl cat`, date du fichier |
| Dim. 18:05 | Revue des accès : ACL **utilisateur** `wb-automation@pve` sur `/pool/lab` jugée redondante avec celle du jeton et retirée | `pveum acl list`, journal des tâches de `pve01` |
| Lun. 07:30 | Échec du contrôle : `fichier de configuration illisible : /home/admin/.config/workbook/pbs-lecture.env` ; alerte `ms-alerte` (crit) | `journalctl -u ms-verif-sauvegardes`, `journalctl -t ms-alerte` |
| 07:52 | Karim : `medictl vm list --pool lab` vide | ticket |
| 09:05 | Prise en charge par l'astreinte ; triage : deux symptômes, hypothèse d'une cause commune (« API Proxmox ») écartée en 5 min : le contrôle échoue **avant** tout appel réseau | journal d'astreinte |
| 09:10 | Communication n° 1 (#astreinte) | canal |
| 09:18 | `lab/bin/check 02 35` et `02 36` : rouges ; `lab/bin/check 02 41` vert (le timer tourne) | journal |
| 09:26 | `systemctl cat ms-verif-sauvegardes.service` : drop-in `20-durcissement.conf` repéré | journal |
| 09:33 | Reproduction : `sudo systemd-run --wait --pipe --collect -p User=admin -p ProtectHome=yes ls ~admin/.config/workbook` → « No such file or directory » | journal |
| 09:41 | Drop-in retiré (le durcissement voulu existait déjà : `ProtectHome=read-only`) ; `daemon-reload` ; relance : **nouvel échec**, « aucune VM du pool lab avec l'étiquette socle n'est visible » | journal |
| 09:45 | Communication n° 2 : première cause corrigée, seconde en analyse, sauvegardes vérifiées à la main sur `pbs01` : présentes | canal |
| 09:55 | `pveum user token permissions wb-automation@pve lab --path /pool/lab` : aucun privilège ; même constat pour `!lecture` ; `pveum acl list` : seules les ACL des jetons restent | journal |
| 10:05 | Sophie Laurent confirme que le retrait de la veille partait d'une mauvaise compréhension de la séparation des privilèges | appel |
| 10:12 | ACL rétablie : `pveum acl modify /pool/lab --users wb-automation@pve --roles WBAutomation` ; `medictl vm list` OK | journal |
| 10:15 | Contrôle relancé sous systemd : succès ; `lab/bin/check 02 35`, `02 36`, `02 41` verts | journal |
| 10:20 | Communication n° 3 : résolu | canal |

## 4. Causes

### 4.1 Causes racines

1. **Drop-in de durcissement incompatible avec le service.** `ProtectHome=yes` rend `/home`,
   `/root` et `/run/user` inaccessibles au service ; or le contrôle lit ses fichiers d'accès dans
   `/home/admin/.config/workbook/`. Le durcissement voulu (lecture seule) était déjà en place dans
   l'unité (`ProtectHome=read-only`) ; le drop-in le remplaçait par une valeur plus stricte.
   Preuve : `systemctl show -p ProtectHome ms-verif-sauvegardes` → `yes` ; reproduction par
   `systemd-run` (09:33).
2. **ACL utilisateur retirée sous des jetons à privilèges séparés.** Les droits effectifs d'un
   jeton à privilèges séparés sont l'**intersection** de ceux du jeton et de ceux de son
   utilisateur. Sans ACL utilisateur sur `/pool/lab`, `wb-automation@pve!lab` et `!lecture` n'y ont
   plus aucun droit : l'API ne renvoie pas d'erreur, elle filtre (liste vide, code 200).
   Preuve : `pveum user token permissions wb-automation@pve lab --path /pool/lab` vide (09:55).

### 4.2 Facteurs contributifs

- Deux changements sans ticket CHG ni test après application (« un durcissement ne peut rien
  casser » ; « une ACL redondante »).
- Le contrôle des sauvegardes n'avait jamais été relancé sous systemd après modification de son
  unité : le guide d'astreinte le demande, la campagne de durcissement ne le savait pas.
- `medictl vm list` présente une liste vide comme un succès : rien ne distinguait « aucune VM » de
  « aucun droit ».
- Masquage : la cause 2 ne pouvait apparaître dans le contrôle des sauvegardes qu'une fois la
  cause 1 corrigée ; elle était en revanche visible dès 07:52 côté `medictl`.

## 5. Détection et diagnostic

- Détection : alerte `ms-alerte` à 07:30 (le chemin d'alerte de M02-E26 a fonctionné), ticket de
  Karim à 07:52 ; prise en charge à 09:05 (pas d'astreinte avant 09:00 le lundi : à revoir).
- Ce qui a accéléré : le message explicite du contrôle (chemin du fichier illisible), le fait de
  lire la configuration **effective** (`systemctl cat`, `systemctl show`) plutôt que le fichier
  d'unité ; les contrôles `lab/bin/check` comme sondes de triage.
- Ce qui a ralenti : l'hypothèse d'une cause unique (« Proxmox ne répond plus ») ; la liste vide
  sans erreur de `medictl`.
- Détection anticipée possible : un passage de test du service après toute modification d'unité
  (aurait échoué dimanche 17:20) ; une sonde quotidienne « le jeton voit au moins N VMs du socle »
  (aurait alerté dimanche 18:05).

## 6. Ce qui a bien fonctionné

- L'alerte d'échec du contrôle est arrivée, avec les lignes utiles du journal.
- Rejouer tous les tests de triage après la première correction a révélé la seconde cause avant
  de clore l'incident.
- Les sauvegardes ont été vérifiées à la main sur `pbs01` dès 09:45 : l'impact réel a été borné tôt.

## 7. Actions

| # | Action | Type | Responsable | Échéance | Ticket |
|---|---|---|---|---|---|
| 1 | Toute modification d'unité systemd de `adm01` passe par une MR de `plateforme/outils` (dossier `systemd/`) et se termine par `systemctl start` + lecture du résultat | prévenir | Karim Benali | J+7 | CHG-385 |
| 2 | `medictl vm list` et `ms-verif-sauvegardes` : avertissement explicite quand la liste est vide (« aucun droit ou aucune VM ? ») et code 1 pour le contrôle (déjà le cas) | détecter | Plateforme | J+14 | DEV-386 |
| 3 | Sonde quotidienne des droits effectifs des jetons d'automatisation (`pveum … permissions`) comparée à une référence versionnée | détecter | Plateforme | J+14 | SEC-386 |
| 4 | Fiche « jetons à privilèges séparés » ajoutée au guide d'astreinte et à la procédure de revue des accès | documenter | Sophie Laurent | J+7 | SEC-387 |
| 5 | Chien de garde de fraîcheur des contrôles planifiés (`ms-verif-fraicheur`, M02-E41) déployé | détecter | Plateforme | J+7 | PLAT-387 |
| 6 | Astreinte joignable dès 07:30 les jours ouvrés pour les alertes `crit` de l'outillage | atténuer | Nadia Roussel | J+30 | — |

## 8. Enseignements

- « Rien vu » n'est pas « rien à signaler » : une API qui filtre au lieu de refuser transforme
  un problème de droits en résultat vide. Les outils doivent traiter un ensemble vide attendu
  comme une erreur.
- Un service planifié ne se teste que **sous systemd** : environnement, utilisateur, protections
  et drop-ins changent tout.
- Après une première correction, rejouer **tous** les tests initiaux : deux changements non
  tracés de la même journée ont toutes les chances de se croiser.

## Annexes

```
admin@adm01:~$ systemctl cat ms-verif-sauvegardes.service | tail -n 8
# /etc/systemd/system/ms-verif-sauvegardes.service.d/20-durcissement.conf
# SEC-380 : durcissement des services planifiés de adm01 (revue S. Laurent / K. Benali)
[Service]
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
admin@adm01:~$ journalctl -u ms-verif-sauvegardes -n 3 -o cat
… ERREUR fichier de configuration illisible : /home/admin/.config/workbook/pbs-lecture.env
ms-verif-sauvegardes.service: Main process exited, code=exited, status=1/FAILURE
ms-verif-sauvegardes.service: Failed with result 'exit-code'.
root@pve01:~# pveum user token permissions wb-automation@pve lecture --path /pool/lab
(aucune ligne)
root@pve01:~# pveum acl list | grep -E 'pool/lab'
│ /pool/lab │ token │ wb-automation@pve!lab     │ WBAutomation │ 1 │
│ /pool/lab │ token │ wb-automation@pve!lecture │ PVEAuditor   │ 1 │
```

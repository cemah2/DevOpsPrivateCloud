# Répétition à blanc de RB-350 — INC-6108

| | |
|---|---|
| Date | 2026-12-08 (une semaine avant l'exercice) |
| Rédaction | équipe Plateforme ; relu par Karim Benali et Nadia Roussel |
| Périmètre | tout RB-350 qui ne touche pas PAR1 : contrôles de préparation, RB-355 (kms01 restauré en 3501 en bac à sable, `bao-par2`), démarrage d'essai d'une instance de chaque application à PAR2 **sans** promotion de la base ni bascule des noms, relevé du témoin |
| Incident | **INC-6108** — variante rencontrée : *exemple ci-dessous, variante 1* (remplace par la tienne) |
| Résultat | répétition rejouée **verte** après réparation ; trois actions de prévention |

> Les heures et durées sont celles d'un lab imaginé pour montrer la forme. Remplace-les par les tiennes.

## 1. Chronologie

| Heure | Étape | Observé | Preuve |
|---|---|---|---|
| 09:30 | Contrôles de préparation (liste de RB-350 §2) | tous verts : `filer.sync` « en cours », `k8s-par2-n01` Ready, `bao-par2` arrêté, dns03 répond | capture `controle-preparation` v0 |
| 09:42 | Relevé du témoin sur la réplique de PAR2 | dernier `PRA-TEMOIN` vu à PAR2 : **07:58** ; PAR1 en écrit un par minute | requête de RB-356 |
| 09:44 | INC-6108 ouvert | « RPO actuel » ≈ 1 h 46 : l'objectif est de 15 min | main courante de répétition |
| 09:50 | Diagnostic | `kubectl cnpg status mediagenda-db-par2` : la réplique rejoue, mais le dernier WAL **disponible** dans `cnpg-k8s-par1` de `s3-02` date de 07:57 ; `s3-01` en a reçu jusqu'à 09:49 | sortie de `aws s3api list-objects-v2` des deux côtés |
| 09:55 | Cause | sur `s3-02`, l'unité `filer-sync@cnpg-k8s-par1` est `inactive (dead)` et **désactivée** depuis 07:58 (`systemctl status`, `journalctl -u`) : coupée pour la montée de SeaweedFS de `s3-02`, jamais relancée | journal systemd |
| 09:57 | Réparation | `systemctl enable --now` de l'unité ; `filer.sync` reprend à son point de contrôle | journal : rattrapage des événements depuis 07:58 |
| 10:06 | Rattrapage | dernier témoin vu à PAR2 : 10:04 (retard 2 min) | requête de RB-356 |
| 10:10 | Répétition rejouée | RB-355 (3501, `bao-par2`), démarrage d'essai des applications à PAR2, relevé du témoin : vert | durées ci-dessous |
| 11:40 | Remise en veille | 3501 détruite, `bao-par2` arrêté, applications de PAR2 à 0 réplica | `check F5 8` vert |

Durées mesurées à la répétition (référence pour le jour J) : RB-355 complet 38 min ; démarrage d'essai des applications 14 min (dont 6 min de tirage d'images depuis `reg02`).

## 2. Cause

Le processus qui copie l'archive de la base vers PAR2 était arrêté depuis près de deux heures, **sans aucune alerte** :
- la supervision du flux regardait l'unité systemd « en échec » (`failed`), pas une unité arrêtée proprement et désactivée ;
- la mesure du retard côté destination (S04) ne portait que sur `medidoc-documents`, pas sur l'archive de la base ;
- la montée de SeaweedFS de `s3-02` n'avait pas de fiche de changement : personne n'avait écrit « relancer la réplication ».

Si PAR1 avait brûlé à 09:44, le RPO réel de MédiAgenda aurait été d'**1 h 46**, pour un objectif de 15 min.

## 3. Ce que la répétition aurait aussi pu trouver (autres variantes)

- **Nœud de `k8s-par2` cordonné** (oubli après une maintenance de `hp01`) : tous les pods d'essai en `Pending` (`0/1 nodes are available: 1 node(s) were unschedulable`). Le voyant « nœud Ready » ne dit rien de la planification.
- **VM `bao-par2` verrouillée** (`lock: backup` laissé par une sauvegarde interrompue) : `qm start 1055` refusé (« VM is locked (backup) »). Un verrou sur une VM arrêtée ne se voit nulle part tant qu'on ne la démarre pas.

## 4. Prévention (actions)

| Action | Ticket | Responsable | Échéance |
|---|---|---|---|
| Contrôle de préparation `outils/pra/controle-preparation.sh` (plateforme/k8s) : effet de chaque flux (âge du dernier témoin vu **à PAR2**), planification possible, VM démarrable, DNS à jour, Argo CD sain, mémoire de `hp01` ; lancé chaque nuit par une minuterie de `adm02` (indicateur `pra_par2_pret` du textfile collector) et en tête de RB-350 | PLAT-3508 | Plateforme | avant l'exercice |
| Alerte « PAR2 non prêt depuis 30 min » et alerte sur l'âge du témoin à PAR2 (S14) | PLAT-3530 | Plateforme | avant l'exercice |
| Toute opération sur une VM de PAR2 passe par une fiche CHG-35xx dont le retour comprend « réplications relancées, `controle-preparation` vert » | CHG-3508 | Karim Benali | immédiat |
| RB-350 §2 : les préalables sont **le résultat** de `controle-preparation`, pas une liste de voyants à regarder | PLAT-3531 | Nadia Roussel | avant l'exercice |

## 5. Décision

Exercice maintenu à la date prévue, sous condition : `controle-preparation` vert la veille au soir et le matin même (Claire Morel, 2026-12-08).

# Mode dégradé à PAR2 — exercice 2026-1 (INC-6109, PLAT-3511)

| | |
|---|---|
| Période | du 2026-12-15 11:20 (reprise de MédiAgenda) au retour à PAR1 (CHG-3512) |
| Pilote | Nadia Roussel ; décisions : Claire Morel |
| Tenu dans | miroir de `plateforme/medisphere` sur `adm02` (branche `main`), versé dans GitLab au retour |

> Exemple de référence : heures et chiffres d'un lab imaginé.

## 1. Ce qui est rendu, ce qui ne l'est pas

| Service | État à PAR2 | Limites acceptées (objectifs.md §3) |
|---|---|---|
| MédiAgenda | ouvert (2 réplicas de l'API, 1 instance de base) | pas de réplique locale de la base : une panne de `k8s-par2-n01` = arrêt ; Valkey reparti vide ; latence p95 mesurée 420 ms (objectif dégradé 1 s) |
| MédiDoc | ouvert | documents déposés entre 10:00 et 10:07 (dernière copie `rclone`) absents : à redéposer si un cabinet le signale |
| Legacy-RDV | ouvert | base de 02:30 : rendez-vous de la matinée à ressaisir (cabinets prévenus par le support) |
| MédiNotif | ouvert depuis 14:12 | un nœud RabbitMQ (file quorum à un membre) ; confirmations de la matinée rejouées (§4) |
| MédiVisio, Data, CI/CD, portail, OpenStack | **fermés** | hors périmètre du PRA v1 (objectifs.md §4) |

## 2. Sauvegardes de PAR2

Tout ce qui a été écrit depuis la reprise n'existe **qu'à PAR2**, sur un seul serveur.

| Quoi | Comment | Fréquence | Où | Vérifié |
|---|---|---|---|---|
| Base `mediagenda-db-par2` | archivage continu des WAL (plugin Barman Cloud) + sauvegarde de base (`ScheduledBackup` quotidien, une manuelle à 14:40) | continu / quotidien | `s3-02`, compartiment `cnpg-k8s-par2` | `kubectl cnpg status` : archivage OK ; sauvegarde `completed` |
| VMs du pool `par2` (`adm02`, `dns03`, `s3-02`, `reg02`, `k8s-par2-n01`, `bao-par2`) | vzdump vers PBS **local** (`ds-lab`, namespace `par2`), mode instantané | quotidien (et 14:40) | `hp01` | tâche OK, restauration d'essai de `dns03` en bac à sable non faite (manque de mémoire) |
| Copie hors de `hp01` | **décision de Claire (15:10)** : export chiffré de la sauvegarde de base et des WAL de la journée vers le disque USB chiffré de l'enveloppe, emporté par Karim chaque soir ; PBS « datastore amovible » écarté pour cet exercice (configuration de PBS interdite dans F5) | quotidien | hors site | somme de contrôle relue |

**Risque accepté** (Claire Morel, 15:10) : une perte de `hp01` dans la journée ferait perdre les écritures depuis la dernière copie hors site (jusqu'à 24 h). Action PLAT-3533 : une cible de sauvegarde hors des deux sites (compartiment chiffré chez un tiers HDS), à chiffrer dans l'ADR-0350 révisée.

## 3. Supervision minimale

`objectifs.md` §4 prévoit une supervision minimale de PAR2 **pendant un PRA** (vague 6 de RB-350), rien en veille. Mise en service à 13:40, après INC-6110, qu'elle aurait signalé (écart E4 du rapport). Décision de Claire (13:40) : +512 Mio pour `adm02`.

- Prometheus, Alertmanager et blackbox_exporter sur `adm02` (paquets Debian), Mailpit de secours sur `adm02` (boîte `cellule-crise`), consulté par la cellule.
- Cibles : node_exporter des VMs de PAR2, les trois noms globaux (sonde HTTPS), l'exportateur de `mediagenda-db-par2` (Service `LoadBalancer` 10.20.20.210, réservé à `adm02`).
- Alertes : nom global indisponible 3 min ; base injoignable ; archivage des WAL arrêté depuis 10 min ; mémoire < 10 % ; disque < 10 % ; horloge non synchronisée.
- Essai : arrêt volontaire de MédiDoc 4 min à 15:30 → courriel reçu à 15:34 dans Mailpit, résolu à 15:37.

## 4. MédiNotif

- 14:05 RabbitMQ (un nœud) et topologie déclarative depuis le miroir de `plateforme/donnees` ; 14:12 worker MédiNotif prêt.
- Règle de rejeu (validée par Julien Petit, 14:20) : confirmations des rendez-vous créés entre **08:50 UTC** (huit minutes avant le dernier témoin retrouvé à PAR2 : marge pour les messages publiés à PAR1 et non consommés avant T0) et **13:14 UTC** (première publication réussie de MédiAgenda à PAR2), canal ≠ `aucun`, hors témoins. Doublons acceptés : une confirmation en double vaut mieux qu'une confirmation perdue. Aucun destinataire journalisé.
- Résultat : 37 demandes publiées et routées (`outils/pra/rejouer-notifications.sh`), consommées en 2 min.
- Rappels « veille » du soir : envoyés par le lot habituel (heure décalée de 20 min).

## 5. Demandes des métiers

| # | Demande | Réponse (date, qui) | Pourquoi |
|---|---|---|---|
| 1 | Julien : livrer ce soir le correctif d'affichage des créneaux | **Non** — 2026-12-15 15:05, Claire Morel | gel des changements pendant le PRA (RB-350, mode dégradé) ; la CI et Harbor sont à PAR1 ; un correctif d'urgence (sécurité, perte de données) passerait par la procédure d'exception, pas un correctif d'affichage |
| 2 | Hugo Bernard : extraction Data de la nuit | **Non, reportée** — 15:05, Claire Morel | Data hors périmètre (objectifs.md §4) ; l'extraction lirait la seule base de production, sans réplique, sur un serveur à la mémoire comptée ; rattrapage d'une nuit après le retour |
| 3 | Cabinet : rendez-vous pris à 10 h 05 introuvable | **Explication + ressaisie** — 15:20, Nadia Roussel (support) | 10:05 est dans la fenêtre perdue (dernier témoin retrouvé : 09:58 heure de Paris) ; il n'est pas à PAR2 ; il pourra être retrouvé dans PAR1 au retour (exercice) — un vrai sinistre l'aurait perdu. Le cabinet ressaisit ; la liste des rendez-vous de la fenêtre perdue est préparée pour le retour (S12) |
| 4 | Sophie : qui s'est connecté à quoi à PAR2 | **Oui** — 16:00, équipe Plateforme | journaux SSH de `hp01`, `adm02` et des VMs (`journalctl -u ssh`), journal d'audit d'OpenBao de `bao-par2`, journal d'audit de l'API de `k8s-par2`, poignées de main `wg1` ; copiés sur le disque de l'enveloppe ; comptes de bris de glace utilisés listés (aucun mot de passe) |
| 5 | Direction : quand revient-on ? | **Pas avant demain 10:00** — 15:30, Claire Morel | retour = changement planifié (CHG-3512) : PAR1 doit être neutralisé, reconstruit en réplique, rattrapé et vérifié avant une coupure courte annoncée aux cabinets la veille |

## 6. Ce qui ne tiendrait pas longtemps

- **Zones DNS secondaires de dns03** : `par1.medisphere.internal` reste secondaire ; elle expire au terme de la valeur *expire* de son SOA (et ses signatures DNSSEC à leur échéance) : au-delà, les noms de PAR1 ne se résolvent plus à PAR2 (sans effet sur les patients, mais sur nos outils).
- **Certificats** : ceux de la Gateway de PAR2 sont émis par l'autorité de PAR2 (renouvelés) ; ceux des VMs de PAR2 émis par `ca01` (ACME) ne se renouvellent pas : liste et échéances relevées (le plus proche : `reg02`, dans 9 jours).
- **Identifiants dynamiques** : les baux du moteur `db-mediagenda` de `bao-par2` se renouvellent ; à surveiller tant que `bao-par2` est la seule copie du coffre (instantané Raft quotidien vers `s3-02` mis en place à 16:30).

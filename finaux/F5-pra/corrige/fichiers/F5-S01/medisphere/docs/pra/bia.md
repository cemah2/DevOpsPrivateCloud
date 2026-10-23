# Analyse d'impact sur l'activité (BIA) — PRA v1

| | |
|---|---|
| Ticket | PLAT-3501 |
| Rédaction | <MOI>, <AAAA-MM-JJ> |
| Sources | Julien Petit (MédiAgenda, volumétrie de <mois>), Nadia Roussel (support, historique des incidents F3), Sophie Laurent (obligations HDS et RGPD), contrat type des cabinets (annexe HDS) |
| Relecture | Julien Petit, Nadia Roussel, Sophie Laurent ; approbation Claire Morel |
| Révision | à chaque nouvelle application, à chaque changement de contrat, et au plus tard un an après la dernière |

> Cette analyse porte sur un **sinistre majeur de PAR1** (perte totale de la salle : incendie, inondation, coupure électrique prolongée, rançongiciel qui chiffre l'hyperviseur). Les pannes partielles relèvent de la haute disponibilité de PAR1 et de l'astreinte (F3), pas du PRA.

## 1. Échelle d'impact

| Niveau | Patients | Cabinets | Conformité | Réputation |
|---|---|---|---|---|
| 1 — faible | gêne, contournement simple | quelques appels de plus | aucun | aucun |
| 2 — sensible | rendez-vous à reprendre par téléphone | standard chargé, retard | information des clients prévue au contrat | quelques plaintes |
| 3 — grave | rendez-vous manqués, soins décalés | standard saturé, perte de chiffre d'affaires | manquement contractuel (reprise « dans la journée ouvrée »), signalement possible | plaintes écrites, presse locale |
| 4 — critique | perte de données de santé, risque pour la prise en charge | résiliations | violation de données (RGPD art. 33 : 72 h), audit HDS défavorable | perte de clients, presse nationale |

## 2. Services

### 2.1 MédiAgenda — prise de rendez-vous en ligne

Volumétrie : 1 200 cabinets, ≈ 9 000 rendez-vous par jour ouvré, dont ≈ 30 % entre 8 h et 10 h (≈ 22 prises par minute en pointe, ≈ 9 par minute en moyenne sur 8 h-18 h).

| Durée d'arrêt | Patients | Cabinets | Conformité | Réputation | Niveau |
|---|---|---|---|---|---|
| 1 h | ≈ 550 rendez-vous non pris en ligne (≈ 1 300 en pointe) ; reportés au téléphone | appels en hausse, secrétariats tendus | aucun | faible | 2 |
| 4 h | ≈ 2 200 à 3 500 rendez-vous à prendre par téléphone ; personnes qui renoncent | standards saturés à partir de la demi-journée (constat de Julien) | limite de l'engagement « dans la journée ouvrée » | plaintes | 3 |
| 1 jour | ≈ 9 000 rendez-vous ; consultations du lendemain sans planning fiable | activité désorganisée | engagement contractuel rompu | presse locale possible | 3 → 4 |
| 3 jours | idem × 3 ; risque sur le suivi de patients chroniques | résiliations probables | audit HDS : PRA inopérant | critique | 4 |

**Perte de données.** Un rendez-vous perdu est un patient qui se présente pour rien ou qui ne vient pas ; il n'est connu que du patient (le cabinet ne le voit pas). 15 min de rendez-vous perdus en pointe ≈ 330 rendez-vous, en moyenne ≈ 135 : chacun doit être retrouvé (courriel de confirmation du patient, journaux) et rappelé. Au-delà d'une heure de perte (≈ 550 rendez-vous), la reconstitution manuelle n'est plus faisable dans la journée.

- **Durée maximale d'interruption admissible (DMIA)** : **une demi-journée ouvrée (≈ 5 h)** : au-delà, les standards saturent et l'engagement « dans la journée » n'est plus tenable.
- **Perte de données maximale admissible (PDMA)** : **1 h** (au-delà, reconstitution impossible dans la journée) ; **cible souhaitée** : quelques minutes.
- **Dépendances métier** : MédiNotif envoie les rappels **à partir** des rendez-vous ; MédiDoc rattache ses documents aux rendez-vous ; l'équipe Data extrait la nuit (non critique).
- **En attendant** : bandeau sur le site public et message vocal des cabinets (« prise de rendez-vous par téléphone ») ; les cabinets gardent leur planning du jour imprimé chaque matin (pratique à généraliser : action PLAT-3501-a) ; le support (Nadia) tient une liste des cabinets à rappeler.

### 2.2 MédiDoc — documents des patients

Volumétrie : ≈ 1 500 dépôts par jour ; consultations surtout pendant les rendez-vous.

| Durée d'arrêt | Impact | Niveau |
|---|---|---|
| 1 h | documents consultés en ligne indisponibles ; le praticien demande au patient sa copie papier | 1 |
| 4 h | dépôts reportés (le patient revient les déposer), consultations sans compte rendu antérieur | 2 |
| 1 jour | prises en charge sans les comptes rendus ; ressaisies | 2 → 3 |
| 3 jours | risque clinique (ordonnances, comptes rendus indisponibles) | 3 |

**Perte de données** : un document perdu est une **perte de donnée de santé** : obligation d'analyse au titre du RGPD (art. 33) et, selon le cas, information des patients ; le patient en garde en général une copie (dépôt depuis son poste), ce qui permet un nouveau dépôt.

- **DMIA** : **1 jour ouvré**.
- **PDMA** : **4 h** (au-delà, on ne peut plus demander raisonnablement aux patients de redéposer) ; cible : 1 h.
- **Dépendances** : MédiAgenda (rattachement aux rendez-vous) ; stockage objet.
- **En attendant** : documents papier apportés par les patients ; dépôts reportés.

### 2.3 Legacy-RDV — prise de rendez-vous des quarante cabinets historiques

Usage : secrétariat au téléphone qui saisit dans Legacy-RDV ; habitué aux pannes (passé avec InfoGér). Sauvegarde **quotidienne** de la base (mariadb-operator, 2 h 30) et pièces jointes sur CephFS.

| Durée d'arrêt | Impact | Niveau |
|---|---|---|
| 1 h | saisie sur papier, ressaisie ensuite | 1 |
| 4 h | ressaisie d'une demi-journée | 2 |
| 1 jour | planning du lendemain incertain ; ressaisie lourde | 2 → 3 |
| 3 jours | désorganisation, risque de résiliation des derniers cabinets | 3 |

- **DMIA** : **1 jour ouvré** (le papier tient une journée).
- **PDMA** : **24 h**, accepté par les cabinets et par Claire : une journée se ressaisit à partir des agendas papier ; un RPO plus court exigerait un flux continu de la base MariaDB vers PAR2, disproportionné pour une application en fin de vie (ADR-0340).
- **En attendant** : agendas papier (procédure existante chez ces cabinets).

### 2.4 MédiNotif — rappels SMS et courriels

Usage : rappels la veille des rendez-vous (envoi en lot en fin d'après-midi) et confirmations immédiates.

| Durée d'arrêt | Impact | Niveau |
|---|---|---|
| 1 h | confirmations en retard | 1 |
| 4 h | si l'arrêt couvre le lot du soir : rappels non envoyés, absences le lendemain (≈ 5 à 10 % de rendez-vous non honorés en plus, estimation de Julien) | 2 |
| 1 jour | une journée sans rappels | 2 |
| 3 jours | absences en hausse durable | 2 → 3 |

- **Perte** : les messages **en vol** (dans RabbitMQ) au moment du sinistre sont perdus ; ils se **rejouent** depuis MédiAgenda (les rendez-vous sont la source). Un rappel en retard de quelques heures reste utile ; un rappel du lendemain non.
- **DMIA** : **8 h ouvrées**, à condition que le lot du soir parte (avec retard).
- **PDMA** : sans objet (aucune donnée propre : tout se recalcule depuis MédiAgenda).

### 2.5 Services hors des applications métier

| Service | Impact d'un arrêt pendant un PRA | Décision (voir `objectifs.md`) |
|---|---|---|
| CI/CD (GitLab, runners, Harbor) | plus de livraison ; un correctif urgent ne passe pas par la chaîne normale | gel des livraisons pendant le PRA ; correctif d'urgence par les miroirs de `adm02` |
| Observabilité complète (Prometheus, Loki, Tempo, Grafana) | on pilote à l'aveugle | supervision **minimale** de PAR2 (sonde `ms-sonde-pra`, état des pods, retard de la base) |
| OpenStack | projets d'essai des équipes de développement | hors PRA |
| Portail Backstage | aucun impact patient | hors PRA |
| Identité (Keycloak, FreeIPA) | plus de SSO pour les équipes | comptes de bris de glace (enveloppe) ; patients non concernés (MédiAgenda n'utilise pas le SSO pour eux) |
| MédiVisio (téléconsultation) | 30 praticiens pilotes reprennent le téléphone | hors PRA v1, à réexaminer au contrat (voir `objectifs.md`) |
| Data (statistiques) | aucune extraction pendant le PRA ; aucun usage clinique | hors PRA v1 |

## 3. Synthèse

| Service | DMIA | PDMA | Niveau à 4 h | Niveau à 1 jour |
|---|---|---|---|---|
| MédiAgenda | ≈ 5 h (demi-journée) | 1 h (cible : minutes) | 3 | 3 → 4 |
| MédiDoc | 1 jour | 4 h (cible : 1 h) | 2 | 2 → 3 |
| Legacy-RDV | 1 jour | 24 h | 2 | 2 → 3 |
| MédiNotif | 8 h ouvrées | sans objet (rejeu) | 2 | 2 |

**Ordre de priorité de la reprise** : MédiAgenda, puis MédiNotif (rejouer les rappels du soir), puis MédiDoc et Legacy-RDV.

## 4. Actions issues de la BIA

- PLAT-3501-a : planning du jour imprimé par les cabinets (communication de Nadia).
- PLAT-3501-b : message vocal et bandeau « mode secours » prêts à l'emploi (`cellule-de-crise.md`, S07).
- PLAT-3501-c : confirmation par courriel de chaque rendez-vous (existe) gardée par le patient : c'est elle qui permet de retrouver un rendez-vous perdu.

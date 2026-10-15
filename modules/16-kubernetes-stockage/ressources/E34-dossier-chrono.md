# Dossier M16-E34 — Rendez-vous disparus (exercice chronométré)

> À ouvrir à T0 seulement, juste après `lab/bin/break 16 34`. Note l'heure maintenant dans la feuille de temps (en bas).

## Le besoin

> **Ticket INC-4334 (suite)** — *De : Nadia Roussel* — *Copie : Julien Petit, Sophie Laurent*
> Le script de nettoyage a supprimé **tous les rendez-vous du praticien `dr-garnier`** dans la base de recette (`mediagenda-db`, espace `mediagenda-recette`). L'heure à laquelle il a été lancé est celle affichée par l'injection (heure de Paris, à la seconde). Depuis, la recette a continué à vivre : d'autres rendez-vous ont été pris, y compris, peut-être, pour `dr-garnier`.
> La démonstration de demain matin se fait sur cette base. On ne la remplace pas, on ne la remonte pas en arrière : on **remet ce qui manque**, et rien d'autre.

## Exigences

| # | Exigence | Détail |
|---|---|---|
| 1 | Récupération | Chaque rendez-vous de `dr-garnier` qui existait **juste avant** l'erreur est de nouveau présent, avec **le même identifiant** et le même contenu (patient, début, durée, motif, date de création). Les patients ont reçu leur identifiant par courriel : un nouvel identifiant ne convient pas. |
| 2 | Écritures postérieures | Tout rendez-vous créé **après** l'erreur (quel que soit le praticien) est toujours présent, inchangé. |
| 3 | Conflits | Si un créneau libéré par l'erreur a été repris entre-temps (même praticien, même heure de début), **le rendez-vous pris après l'erreur est conservé** ; l'ancien n'est pas réinséré, et son identifiant figure dans le compte rendu pour que le secrétariat rappelle le patient. |
| 4 | Base de production | `mediagenda-db` de `mediagenda-recette` n'est ni arrêté, ni remplacé, ni restauré par-dessus, ni basculé : même objet `Cluster`, même timeline qu'à T0. |
| 5 | Archives | Aucun cluster créé pour l'enquête n'écrit dans le compartiment `cnpg-k8s-par1` ; l'archivage continu de `mediagenda-db` est toujours actif à T3. |
| 6 | Nettoyage | Tout ce qui a été créé pour l'enquête (cluster temporaire, PVC, objets de travail, fichiers d'extraction sur `adm01`) est supprimé à T3. Les fichiers d'extraction contiennent des données de santé : ils ne quittent pas `adm01` et sont effacés (`shred`). |
| 7 | Compte rendu | `docs/kubernetes/stockage/tests/chrono-pitr-<AAAAMMJJ>.md` dans `plateforme/medisphere` : heure de l'erreur, instant de récupération choisi et pourquoi, nombre de rendez-vous remis, identifiants des conflits, jalons T0-T3, gestes manuels. **Aucun nom de patient**, uniquement des identifiants. |
| 8 | Traçabilité | RB-162 mis à jour par MR (ce qui t'a manqué, ce qui t'a fait perdre du temps). |

## Vérification

À T3, depuis `adm01` : `lab/bin/check 16 34`. Tout doit être vert. Pour recommencer depuis l'état initial : `lab/bin/break 16 34 --annuler`, puis une nouvelle injection.

## Feuille de temps

| Jalon | Définition | Heure | Écart depuis T0 | Gestes manuels / commentaire |
|---|---|---|---|---|
| T0 | Injection, heure de l'erreur connue | | 0 | |
| T1 | Cluster temporaire en cours de récupération (manifeste appliqué), instant cible justifié | | | |
| T2 | Rendez-vous manquants identifiés dans le cluster temporaire et réinjectés dans `mediagenda-db` | | | |
| T3 | Contrôles faits, nettoyage fait, `lab/bin/check 16 34` entièrement vert | | | |

**Retour d'expérience** (une demi-page, en tête du compte rendu) : ce qui a pris le plus de temps, les gestes manuels et l'outillage qui les aurait évités, ce que RB-162 ne disait pas, comment descendre sous 20 minutes.

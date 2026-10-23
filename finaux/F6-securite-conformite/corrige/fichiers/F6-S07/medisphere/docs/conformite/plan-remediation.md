# Plan de remédiation — audit à blanc 2026

> SEC-3607 (F6-S07). Rédigé par la Plateforme et la RSSI, arbitré par Claire Morel le 2026-11-24. Suivi : chaque fiche `ecarts/ECA-36xx.md` porte son statut ; ce plan est revu chaque semaine jusqu'à la clôture des écarts majeurs.

## 1. Méthode de priorisation

On priorise par le **risque** pour les patients et les clients, pas par la gravité d'audit ni par la facilité :

- **Impact** (1 à 4) : 4 = données de santé exposées ou altérées, ou incapacité à le savoir ; 3 = atteinte à la disponibilité ou à la preuve ; 2 = défaut de pilotage ; 1 = cosmétique.
- **Vraisemblance** (1 à 4) : 4 = le scénario se produit déjà ou se produira sans action ; 3 = une erreur ordinaire suffit ; 2 = il faut une action malveillante interne ou un concours de circonstances ; 1 = improbable.
- **Niveau** = impact × vraisemblance ; priorité **P1** si ≥ 9, **P2** de 5 à 8, **P3** en dessous. Les **dépendances** ajustent l'ordre à niveau égal.

## 2. Écarts, risque, actions

| Écart | Scénario de risque | I | V | Niveau | Priorité | Actions | Responsable | Échéance | Preuve de clôture attendue |
|---|---|---|---|---|---|---|---|---|---|
| ECA-3606 | des captures de dossiers patients stockées hors plateforme HDS, chez un éditeur soumis au droit américain ; clients non informés | 4 | 4 | **16** | **P1** | consigne et purge (fait) ; cartographie validée et publiée ; avenants clients ; clauses fournisseurs ; choix d'outil | Thomas Renaud | publication 2026-11-27 ; avenants 2027-01-31 | page publiée, accusé de purge de l'éditeur, avenant type signé |
| ECA-3603 | une identité de lecture de `s3-01` (ou une copie à PAR2) suffit pour lire des Secrets et des données de santé | 4 | 3 | **12** | **P1** | chiffrement des sauvegardes et des exports, clé dans OpenBao, restauration éprouvée (F6-S09) | Karim Benali | 2026-12-18 | restauration d'essai réussie ; lecture directe du compartiment illisible |
| ECA-3601 | une action malveillante d'un administrateur effacée de ses traces ; une enquête sans valeur probante | 4 | 2 | 8 | P2 → **avancé en P1** | archive verrouillée des six sources, intégrité signée, conservation écrite (F6-S08) | Karim Benali | 2026-12-11 | contrôle d'intégrité vert, suppression refusée en `COMPLIANCE` |
| ECA-3605 | un incident de sécurité mal contenu, des preuves détruites, une notification hors délai | 4 | 2 | 8 | P2 | RB-360, RB-361, kit forensique, modèles de notification, exercice (F6-S10) | Sophie Laurent | 2027-01-15 | exercice réalisé et post-mortem |
| ECA-3602 | une vulnérabilité critique exploitée en recette puis en production faute de délai | 3 | 3 | 9 | **P1** | politique de délais, exceptions datées qui expirent, tableau du retard (F6-S09) | Sophie Laurent / Plateforme | 2026-12-18 | politique publiée, aucune critique en retard au tableau |
| ECA-3604 | un accès oublié (prestataire, essai) réutilisé | 3 | 2 | 6 | P2 | deuxième revue mensuelle, couverture étendue, contrôles de départ complétés | Sophie Laurent | 2026-12-11 | revue 2026-12 publiée |

**Pourquoi ECA-3601 est avancé** : il ne vaut « que » 8 seul, mais ECA-3605 en dépend (une investigation sans journaux inaltérables ne prouve rien) et l'incident simulé de janvier s'appuiera dessus. **Pourquoi ECA-3606 passe en premier** : c'est le seul écart où des données de santé quittent **aujourd'hui** le périmètre maîtrisé ; ses premières actions (consigne, purge) ne coûtent presque rien.

## 3. Calendrier

| Semaine | Travaux | Scénario |
|---|---|---|
| 2026-11-23 | ECA-3606 : consigne, purge, cartographie publiée | S07 |
| 2026-11-30 → 12-11 | ECA-3601 (archive des journaux), ECA-3604 (deuxième revue) | S08 |
| 2026-12-07 → 12-18 | ECA-3602, ECA-3603 | S09 |
| 2026-12-18 → 2027-01-04 | **gel** de fin d'année (F4) : documentation seulement | — |
| 2027-01-04 → 01-15 | ECA-3605 : préparation à l'incident, exercice | S10 |
| 2027-02 | audit de suivi interne | S14 |

Capacité : une personne de la Plateforme à mi-temps sur la remédiation pendant six semaines, Sophie et Thomas pour les documents ; ce plan ne retarde aucune montée planifiée du trimestre.

## 4. Risques acceptés temporairement

| Risque | Jusqu'à | Mesure compensatoire | Accepté par |
|---|---|---|---|
| Sauvegardes non chiffrées (ECA-3603) | 2026-12-18 | accès en lecture aux compartiments de sauvegarde réduits à Velero et au compte de restauration ; journal d'accès de `s3-01` relu chaque semaine | Claire Morel |
| Journaux non inaltérables (ECA-3601) | 2026-12-11 | export quotidien du locataire `audit` par `ms-preuves` dans `preuves-conformite` | Sophie Laurent |
| Pas de procédure d'incident de sécurité (ECA-3605) | 2027-01-15 | RSSI pilote de tout incident de sécurité ; quarantaine réseau du M26 disponible | Sophie Laurent |

## 5. Suivi

Statut de chaque écart dans sa fiche (`ouvert`, `en cours`, `clos`) ; un écart n'est clos qu'avec sa **preuve de clôture**, vérifiée par une autre personne que celle qui a corrigé. Le registre est relu chaque lundi par Sophie ; tout retard de plus de deux semaines remonte à Claire.

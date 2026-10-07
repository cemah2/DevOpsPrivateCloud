# ADR-0040 — Appliquer la configuration du socle uniquement par la CI GitLab

- Statut : accepté
- Date : 2026-10-XX
- Décideurs : Claire Morel (responsable infrastructure), équipe Plateforme
- Consultés : Karim Benali (standards), Sophie Laurent (RSSI), Nadia Roussel (support et astreinte)

## Contexte et problème

Depuis le module 04, la configuration du socle (`gw01`, `adm01`, `dns01`, `git01`, `runner01`) est décrite dans
`plateforme/ansible`. Trois chemins permettent aujourd'hui de l'appliquer : un poste d'administration (`adm01`),
le pipeline GitLab (job `appliquer`, M04-E27) et Semaphore UI sur `sem01` (M04-E28). Ils produisent trois
journaux différents, détiennent chacun une clé `root` sur tout le socle, et rien n'empêche deux applications
simultanées par deux chemins. L'audit HDS demande de prouver qui a modifié quoi, quand, et que l'état réel est
resté conforme. Il faut un chemin normal unique, des exceptions encadrées, et décider du sort de `sem01`.

## Facteurs de décision

- Traçabilité HDS / ISO 27001 : tout changement relié à une MR relue, un auteur, un commit, un journal conservé.
- Séparation des rôles : qui écrit le changement n'est pas seul à décider de l'appliquer.
- Surface d'attaque : nombre de machines qui détiennent une clé `root` du socle et un mot de passe Vault.
- Une seule application à la fois sur une même cible.
- Disponibilité : que faire quand GitLab ou le runner est en panne, à 3 h du matin.
- Coût d'exploitation pour une équipe de quatre personnes (mises à jour, sauvegardes, supervision).
- Besoins de l'astreinte de premier niveau (Nadia) : voir l'état, diagnostiquer, sans terminal.

## Options envisagées

1. Application depuis les postes d'administration.
2. CI GitLab seule (job `appliquer` manuel sur `main`).
3. Semaphore UI seul (MR et tests en CI, application uniquement dans Semaphore).
4. CI pour les changements, Semaphore pour l'exploitation (tâches d'astreinte, ré-application ciblée).
5. AWX / Ansible Automation Platform (en remplacement de 3 ou 4).
6. `ansible-pull` sur chaque hôte (mode *pull* planifié).

## Décision

Option retenue : **2, CI GitLab seule**, parce qu'elle est la seule à satisfaire à la fois la traçabilité de
bout en bout (MR → pipeline → déploiement de l'environnement `lab/socle`), l'unicité de l'exécutant (un
`resource_group` couvre application et détection de dérive) et le minimum de détenteurs de secrets, pour un coût
d'exploitation nul (GitLab et `runner01` existent déjà).

- **Chemin normal** : branche `conf/*` → MR (ansible-lint, Molecule des rôles touchés, `check-socle`, relecture)
  → fusion dans `main` → job `appliquer` lancé par un Maintainer, contrôle de convergence à zéro. Une
  ré-application ciblée passe par le même job avec la variable de job manuel `LIMITE` (`--limit`).
- **Détection de dérive** : pipeline planifié quotidien (M04-E29). Une dérive ouvre le ticket `derive` ; on la
  corrige par une application (ou une MR si l'écart doit devenir la règle), jamais à la main.
- **Secrets** : identité Vault `lab` pour les jobs du socle ; `critique` seulement pour l'environnement
  `lab/socle` (CI) et pour les deux Maintainers sur `adm01` (M04-E30). Rotation : RB-041.
- **Bris de glace** (GitLab ou le runner indisponible, incident qui ne peut pas attendre) :
  1. un Maintainer ouvre un ticket INC et annonce l'intervention dans le canal de l'équipe ;
  2. il suspend les pipelines planifiés (`derive`) ;
  3. depuis `adm01`, sur un clone à jour de `main` (ou de l'étiquette du dernier déploiement), il exécute
     `uv run ansible-playbook playbooks/site.yml --limit <hôtes> --diff 2>&1 | tee docs/socle/journal/<date>-INC-xxxx.log`
     (journal versionné dans `plateforme/medisphere`) ;
  4. toute modification du code passe ensuite par une MR qui cite l'INC ;
  5. le retour au chemin normal est constaté par un `appliquer` CI suivi d'une détection de dérive « conforme ».
  Un bris de glace sans ticket INC est un écart de sécurité.
- **Concurrence** : un seul exécutant en temps normal ; en bris de glace, l'étape 2 et l'annonce tiennent lieu de
  verrou (accepté : au plus une intervention de ce type par trimestre attendue).
- **`sem01`** : Semaphore est évalué (M04-E28) mais **non retenu** à ce stade. Le rôle `semaphore` et le compte
  rendu d'évaluation restent dans le dépôt ; la VM 2041 est **détruite** à la fin du module, la clé
  `ansible-semaphore` retirée des clés autorisées par le rôle `base`, ses secrets retirés du registre.

### Conséquences

- Positives : un seul journal de référence (déploiements de `lab/socle`, artefacts conservés 1 an) ; une seule
  machine (`runner01`) détient la clé `ansible-ci` ; aucune VM de plus à maintenir ; la dérive est mesurée par le
  même exécutant que l'application.
- Négatives : l'astreinte de premier niveau ne peut pas appliquer seule (elle n'est pas Maintainer) : elle
  diagnostique, puis appelle le niveau 2. `runner01` et GitLab deviennent critiques pour **changer** le socle
  (pas pour le faire fonctionner). Pas d'interface dédiée à l'astreinte.
- Actions induites : RB-040 (appliquer un changement) précise le chemin normal et la variable `LIMITE` ;
  RB-041 (rotation Vault) ; procédure de bris de glace ajoutée au guide d'astreinte ; destruction de `sem01` et
  retrait de sa clé (M04-E46) ; supervision de `runner01` et du pipeline planifié (module 21) ; réévaluer
  Semaphore (ou une interface d'astreinte) avec l'IdP central (module 24) et quand l'équipe dépassera six personnes.

## Analyse des options

### 1. Postes d'administration
- Pour : immédiat, sans dépendance ; indispensable en dernier recours.
- Contre : aucune trace centralisée, versions d'Ansible et de clés différentes par poste, secrets sur chaque poste,
  pas de garde-fou contre les applications simultanées. Gardé seulement comme bris de glace.

### 2. CI GitLab seule (retenue)
- Pour : la MR, le pipeline et le déploiement sont un seul enregistrement ; variables protégées, `resource_group`,
  environnement ; rien de nouveau à exploiter.
- Contre : GitLab CE n'a pas d'environnements protégés (seuls les Maintainers peuvent lancer le job, par la
  protection de `main`) ; pas d'interface pour un non-développeur ; dépend de `git01` et `runner01`.

### 3. Semaphore seul
- Pour : interface claire, historique par tâche, rôles fins (Task Runner), planifications.
- Contre : une VM de plus avec une clé `root` du socle et un magasin de secrets à protéger (clé
  `access_key_encryption`) ; journal séparé de la MR ; Semaphore désactive par défaut la vérification des clés
  d'hôte et clone les dépôts SSH sans vérifier le serveur (M04-E28) ; il dépend aussi de GitLab pour cloner.

### 4. CI + Semaphore
- Pour : répond au besoin de Nadia.
- Contre : deux exécutants qui écrivent sans verrou commun (un verrou côté cibles serait à développer et à
  maintenir) ; deux jeux de secrets ; deux journaux à rapprocher pour l'audit. Coût supérieur au bénéfice à
  cinq hôtes.

### 5. AWX
- Pour : la référence fonctionnelle (RBAC fin, inventaires, approbations, API).
- Contre : aucune version depuis la 24.6.1 (juillet 2024), développement suspendu ; exige Kubernetes (opérateur) ;
  mises à jour lourdes — l'expérience d'InfoGér. Écarté.

### 6. `ansible-pull`
- Pour : chaque hôte converge seul, même si la forge tombe ; dérive corrigée automatiquement.
- Contre : chaque hôte doit pouvoir lire le dépôt et détenir le mot de passe Vault ; correction automatique d'une
  dérive sans analyse ; pas de revue de l'aperçu avant application ; journaux dispersés. Écarté pour le socle,
  à reconsidérer pour des parcs homogènes et nombreux.

## Liens

- PLAT-558 (M04-E27), PLAT-561 (M04-E28), SEC-564 (M04-E29), SEC-567 (M04-E30), PLAT-570 (cet ADR).
- ADR-0010 (forge), RB-040, RB-041 ; `docs/socle/registre-secrets.md`.

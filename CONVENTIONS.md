# CONVENTIONS.md — Règles de rédaction et de structure

> Ce fichier fixe **comment** le workbook est écrit. Il s'applique à tous les modules et finaux. Le module 00 est le **gabarit de référence** : en cas de doute, on reproduit sa forme.

---

## 1. Arborescence

```
.
├── README.md                  # Présentation pour l'apprenant
├── PLAN.md                    # Plan directeur (fil rouge, réseau, modules)
├── CONVENTIONS.md             # Ce fichier
├── AVANCEMENT.md              # État de production
├── REPRISE.md                 # Prompts pour reprendre dans une nouvelle conversation
├── CLAUDE.md                  # Consignes pour Claude (production)
├── lab/
│   ├── lib/check-lib.sh       # Bibliothèque commune des scripts de vérification
│   ├── bin/                   # Outils communs (lancer un check, injecter une panne)
│   └── topologie.md           # Schéma et inventaire de référence du lab
├── modules/
│   └── NN-slug/               # ex. 05-iac-terraform
│       ├── README.md          # Fiche du module (objectifs, prérequis, profil, carte des exercices)
│       ├── enonce/
│       │   ├── 00-introduction.md
│       │   ├── 01-decouverte.md
│       │   ├── 02-operationnel.md
│       │   ├── 03-production.md
│       │   ├── 04-expert.md
│       │   └── 05-mini-projet.md
│       ├── ressources/        # Fichiers fournis à l'apprenant (configs cassées à réviser, squelettes, données)
│       ├── checks/            # Scripts de vérification : check-EXX.sh
│       └── corrige/           # ⚠️ Corrigé — ne pas ouvrir avant d'avoir cherché
│           ├── 01-decouverte.md
│           ├── 02-operationnel.md
│           ├── 03-production.md
│           ├── 04-expert.md
│           ├── 05-mini-projet.md
│           ├── fichiers/      # Solutions complètes (code, configs) référencées par le corrigé
│           └── pannes/        # Scripts d'injection de pannes (break & fix) — ils révèlent la panne
├── finaux/
│   └── FN-slug/               # même structure que modules/
└── annexes/
    ├── prerequis.md           # Graphe des dépendances entre modules
    ├── certifications.md      # Correspondance certifications ↔ exercices
    ├── glossaire.md
    └── decouverte/            # Fiches courtes sur les technos hors périmètre
```

Slugs des modules : `00-lab`, `01-git`, `02-scripting`, `03-images`, `04-ansible`, `05-iac`, `06-services-socle`, `07-reseau-ha`, `08-ceph`, `09-cluster-proxmox`, `10-openstack`, `11-bare-metal`, `12-conteneurs`, `13-registre-supply-chain`, `14-kubernetes-admin`, `15-kubernetes-reseau`, `16-kubernetes-stockage`, `17-packaging`, `18-distributions`, `19-ci`, `20-gitops`, `21-metriques`, `22-logs`, `23-traces`, `24-identite`, `25-secrets`, `26-durcissement`, `27-donnees-messaging`, `28-plateforme-dev`, `29-tests-resilience`. Finaux : `F1-day0`, `F2-day1`, `F3-astreinte`, `F4-changements`, `F5-pra`, `F6-securite-conformite`, `F7-capstone`.

## 2. Progression : les paliers

Chaque module est découpé en **5 paliers**, un fichier chacun :

| Palier | Fichier | Ce qu'on y fait | Part des exercices |
|---|---|---|---|
| 1. Découverte | `01-decouverte.md` | Comprendre les concepts, manipuler, installer | ~20 % |
| 2. Opérationnel | `02-operationnel.md` | Traiter les tickets courants du quotidien | ~30 % |
| 3. Production | `03-production.md` | HA, sécurité, automatisation, supervision, sauvegarde de la brique | ~25 % |
| 4. Expert | `04-expert.md` | Break & fix, cas limites, performance, internals | ~20 % |
| 5. Mini-projet | `05-mini-projet.md` | Livrer la brique dans l'infrastructure MédiSphère (intégration) | 1 projet |

`00-introduction.md` contient : contexte MédiSphère du module, concepts clés (synthèse, pas un cours exhaustif — renvoyer à la doc officielle), schéma d'architecture du module, préparation de l'environnement.

## 3. Volume cible

| Niveau | Exercices (hors mini-projet) | Dont break & fix | Dont questions/revue/rédaction |
|---|---|---|---|
| Cœur | 40 à 60 | ≥ 8 | ≥ 8 |
| Secondaire | 20 à 30 | ≥ 4 | ≥ 4 |
| Final | 10 à 20 scénarios longs | (selon scénario) | ≥ 2 livrables écrits |

**Qualité avant quantité** : aucun exercice de remplissage, aucun doublon. Deux exercices qui entraînent exactement le même geste doivent être fusionnés.

## 4. Identification et métadonnées

- Identifiant : `M<NN>-E<XX>` pour les modules (ex. `M05-E17`), `F<N>-S<XX>` pour les scénarios des finaux. Numérotation continue sur tout le module (pas de remise à zéro par palier).
- Difficulté : `★` (guidé) · `★★` (autonome avec indications) · `★★★` (autonome, recherche dans la doc nécessaire) · `★★★★` (niveau expert / incident réel).
- Types :

| Code | Type | Description |
|---|---|---|
| `LAB` | Lab guidé | Étapes indiquées, l'apprenant exécute et comprend |
| `LIBRE` | Lab libre | Objectif et contraintes seulement, l'apprenant conçoit la solution |
| `BF` | Break & fix | Un environnement est cassé (par script d'injection), il faut diagnostiquer et réparer |
| `Q` | Questions | Questions ouvertes ou QCM argumentés, sans manipulation |
| `REV` | Revue | Revue d'une config/d'un code fourni contenant des défauts (dans `ressources/`) |
| `RED` | Rédaction | Runbook, ADR, post-mortem, documentation, réponse à un ticket |
| `CHRONO` | Chronométré | Conditions d'examen, temps limité, sans corrigé consulté |

## 5. Gabarit d'un exercice (énoncé)

```markdown
### M05-E17 — Verrouiller l'état Terraform partagé  `LAB` `★★`

> **Ticket PLAT-142** — *De : Karim Benali*
> Hier, deux `tofu apply` lancés en parallèle par Julien et moi ont corrompu l'état du projet `socle`.
> Il faut que ça ne puisse plus arriver.

**Objectifs pédagogiques**
- Comprendre le rôle du verrou d'état et ses mécanismes selon le backend.
- Configurer le verrouillage natif S3 sur MinIO.

**Prérequis** : M05-E12 (backend S3 configuré).
**Durée indicative** : 45 min.

**Contexte technique** (si nécessaire) : informations factuelles dont l'apprenant a besoin et qu'il ne peut pas deviner (adresses, noms, contraintes).

**Travail demandé**
1. …
2. …

**Critères de réussite**
- [ ] Deux `apply` simultanés : le second échoue avec un message de verrou explicite.
- [ ] …

**Vérification** : `lab/bin/check 05 17`

<details><summary>Indice 1</summary>

…orientation générale…
</details>

<details><summary>Indice 2</summary>

…piste plus précise (sans donner la solution)…
</details>

**Pour aller plus loin** (facultatif) : …
```

Règles :
- Le **ticket** est écrit dans le ton de l'entreprise (un vrai besoin, une vraie contrainte), signé par un personnage de `PLAN.md`. Numéros de ticket : `PLAT-` (plateforme), `SEC-` (sécurité), `INC-` (incident), `CHG-` (changement), `DEV-` (demande des équipes de dev).
- Pour un `LAB` guidé, les étapes peuvent contenir des commandes. Pour un `LIBRE`, **aucune** commande : seulement objectifs, contraintes et critères.
- Les **critères de réussite** sont vérifiables (observables par une commande), jamais « avoir compris X ».
- Les indices sont progressifs (2 ou 3), en `<details>` pour ne pas être lus par accident. **Aucune solution dans l'énoncé.**
- Les exercices `Q` présentent les questions numérotées ; les réponses sont exclusivement dans le corrigé.
- Les exercices `BF` indiquent : le symptôme rapporté (comme un utilisateur le décrirait), la commande d'injection (`lab/bin/break <module> <exercice>`), et le temps cible. Ils ne révèlent jamais la cause.

## 6. Gabarit d'un corrigé

```markdown
### M05-E17 — Verrouiller l'état Terraform partagé

**Solution**
…étapes, commandes, fichiers (ou lien vers `fichiers/M05-E17/`)…

**Explications**
Pourquoi cette solution fonctionne, ce qui se passe sous le capot.

**Alternatives**
Autres approches valables et leurs compromis (ex. DynamoDB-like vs verrou natif, Consul, PostgreSQL backend).

**Pièges classiques**
- …

**En production chez MédiSphère**
Ce qu'on ajouterait dans un vrai contexte (supervision, procédure, sécurité).
```

Pour un `BF`, la section **Solution** est remplacée par **Démarche de diagnostic** : symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine → correctif → prévention. La démarche compte plus que le correctif.

Pour un `Q`, chaque réponse est argumentée (pas seulement « réponse B »), avec la raison pour laquelle les autres options sont fausses.

## 7. Scripts de vérification

- Un script par exercice vérifiable : `modules/NN-slug/checks/check-EXX.sh`. Les exercices `Q` et `RED` n'ont pas de script (auto-évaluation via le corrigé).
- Lancement : `lab/bin/check <NN> <XX>` depuis `adm01` (le poste d'admin du lab), qui exécute le script avec la bibliothèque `lab/lib/check-lib.sh`.
- Le script **n'affiche jamais la solution** ; il dit ce qui est OK/KO avec un message orienté symptôme (« la VM 1010 ne répond pas au ping depuis adm01 »), pas solution (« ajoute la route X »).
- Il est **en lecture seule** : il ne modifie rien sur le lab.
- Code de sortie : `0` si tous les contrôles passent, `1` sinon.
- Fonctions disponibles (voir `lab/lib/check-lib.sh`) : `check_cmd`, `check_output`, `check_ssh`, `check_port`, `check_http`, `check_dns`, `skip`, `summary`.
- Les scripts doivent passer `shellcheck` sans avertissement.

## 8. Injection de pannes (break & fix)

- Un script par exercice `BF` : `modules/NN-slug/corrige/pannes/break-EXX.sh` (dans le corrigé, car il révèle la panne).
- Lancement : `lab/bin/break <NN> <XX>`. L'apprenant ne lit pas le script.
- Un script peut tirer **au hasard** une panne parmi plusieurs variantes (`--variante N` pour forcer) ; le corrigé traite chaque variante.
- Chaque script de panne :
  - définit une fonction `main()` (appelée par `lab/bin/break` avec les arguments `--variante N` / `--annuler`) et peut utiliser les fonctions de `lab/lib/check-lib.sh` (notamment `remote hôte commande`) ;
  - affiche uniquement le symptôme utilisateur ;
  - agit **uniquement** sur des ressources du lab (jamais sur les VMs hors pool `lab`, jamais sur `hp01` hors PBS) ;
  - enregistre ce qu'il a fait dans `/var/lib/workbook/pannes.log` sur l'hôte ciblé (pour pouvoir annuler) ;
  - fournit une option `--annuler` qui restaure l'état sain (filet de sécurité si l'apprenant abandonne).

## 9. Style rédactionnel

- **Français**, tutoiement de l'apprenant. Termes techniques anglais conservés quand c'est l'usage du métier (*rollback*, *pipeline*, *namespace*), avec la traduction à la première occurrence si utile.
- Phrases courtes, précises. Pas de remplissage, pas de « il est important de noter que ».
- Les commandes sont dans des blocs de code avec l'invite indiquant **où** les lancer :
  ```
  root@pve01:~# pvesh get /nodes
  admin@adm01:~$ ansible-inventory --graph
  ```
- Valeurs à adapter par l'apprenant notées `<EN-MAJUSCULES>` (ex. `<LAN-MAISON>`), toujours expliquées à la première occurrence.
- **Avertissements** pour toute action destructrice ou risquée :
  > ⚠️ **Attention** : cette commande supprime … Vérifie d'abord que …
- Toute référence à une adresse, un nom d'hôte, un VLAN ou un VMID doit être **conforme à `PLAN.md`**.
- Lien vers la documentation officielle quand un concept n'est pas expliqué en entier (« Pour aller plus loin »).

## 10. Exactitude technique

- Les commandes, options et syntaxes doivent correspondre aux **versions de référence** de `PLAN.md` §6. En cas de doute sur une option, préférer une formulation qui oblige l'apprenant à consulter `--help` / la doc plutôt qu'inventer.
- Ne jamais inventer d'option, de clé de configuration ou de champ d'API. Si un détail dépend de la version, le signaler.
- Les fichiers de solution (`corrige/fichiers/`) doivent être complets et cohérents entre eux (un rôle Ansible complet, pas un extrait qui ne tourne pas).
- Le corrigé indique explicitement les points « non testés en conditions réelles » s'il y en a, pour que les retours de l'apprenant les corrigent.

## 11. Grille de relecture (appliquée à chaque module)

Un module n'est marqué « relu » dans `AVANCEMENT.md` que si :

1. **Conformité au plan** : adresses, noms, VMID, VLAN, personnages, versions conformes à `PLAN.md`.
2. **Prérequis** : rien n'est utilisé qui ne soit enseigné dans un module antérieur (ou explicitement fourni).
3. **Volume** : cibles de la section 3 atteintes, répartition par palier respectée, pas de doublon.
4. **Énoncés** : aucun élément de solution dans les énoncés ; critères de réussite vérifiables ; indices progressifs.
5. **Corrigés** : chaque exercice de l'énoncé a son corrigé, et inversement ; les `BF` ont une démarche de diagnostic ; les `Q` sont argumentés.
6. **Scripts** : un check par exercice vérifiable, une panne par `BF`, `shellcheck` propre, `--annuler` présent.
7. **Exactitude** : pas d'option inventée, commandes plausibles pour les versions de référence.
8. **Fil rouge** : le mini-projet intègre la brique dans MédiSphère et prépare les modules suivants.

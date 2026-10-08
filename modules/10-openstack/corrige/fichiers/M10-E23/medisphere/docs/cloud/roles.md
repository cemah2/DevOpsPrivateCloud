# Rôles et politiques d'accès d'OpenStack PAR1

> M10-E23 (SEC-1133). Politiques par défaut de la série 2026.1 (« secure RBAC » : `enforce_new_defaults` actif, portée toujours vérifiée) + surcharges de `etc/kolla/config/nova/policy.yaml` (et sa copie pour Horizon).

## 1. Qui a quoi

| Groupe | Rôle | Où | Pourquoi |
|---|---|---|---|
| compte `admin` (domaine `Default`) | `admin` | projet `admin` | administration du cloud (**global** : `admin` ne regarde pas le projet) ; comptes de service `svc-*` de `Default` selon leur besoin |
| `equipe-plateforme` | `member` / `reader` | `plateforme` / projets des équipes | E05 |
| `equipe-<équipe>` | `member` (dev), `reader` (prod) | projets de l'équipe | RB-100 |
| `equipe-securite` | `reader` **hérité** | domaine `medisphere` → tous ses projets, présents et futurs | audit HDS |
| `equipe-support` | `reader` + `support` | `mediagenda-dev`, `mediagenda-prod` (projet par projet) | dépannage des instances |

Chaîne d'implications de Keystone : `admin` → `manager` → `member` → `reader`.

## 2. Matrice rôle × action (instances, volumes, réseau)

| Action | `reader` | `support` (+ `reader`) | `member` | `manager` | `admin` |
|---|---|---|---|---|---|
| Lister, afficher les instances | oui | oui | oui | oui | oui (tous projets) |
| Redémarrer, arrêter, démarrer | non (403) | **oui** (surcharge) | oui | oui | oui |
| Sortie console, console distante | non | **oui** (surcharge) | oui | oui | oui |
| Créer, supprimer, redimensionner une instance | non | non | oui | oui | oui |
| Créer, attacher un volume | non | non | oui | oui | oui |
| Modifier un groupe de sécurité, un réseau | non | non | oui | oui | oui |
| Poser un quota, créer un gabarit public, un réseau externe | non | non | non | non | oui |
| Voir les autres projets | non | non | non | non | **oui** |

`manager` : prévu pour les actions « de chef de projet » ; pris en charge inégalement selon les services en 2026.1 (à revoir avant de le donner).

## 3. Règles

- Jamais `admin` sur un projet d'équipe (E13).
- Groupes, comptes et attributions vivent dans `donnees/identite.yml` de `plateforme/openstack` (E05) ; seule l'attribution héritée de `equipe-securite` est posée par `outils/attribution-audit-heritee.sh` (module Ansible sans héritage).
- Un rôle personnalisé se décrit ici, se code dans `policy.yaml` (service **et** Horizon), se teste avec un compte du rôle (cloud `medisphere-support`, `medisphere-audit`) avant fusion.
- Toute surcharge de politique reprend la règle par défaut de **notre** version (fichier d'exemple de `oslopolicy-sample-generator`) : à relire à chaque mise à jour d'OpenStack (RB-101).

# Images de base de MédiSphère

| | |
|---|---|
| **Statut** | En vigueur |
| **Version** | 1.0 — 2026-10 (M12-E27, ticket PLAT-1327) |
| **Propriétaire** | Équipe Plateforme (Karim Benali) ; validation sécurité : Sophie Laurent |
| **Revue** | trimestrielle, et à chaque changement de registre (Harbor, M13) |
| **Code** | projet `plateforme/images-base` ; contrôle CI : `plateforme/ci-templates`, `images-autorisees.yml` |

## 1. Pourquoi

Une image d'application hérite de tout ce que contient son image de base : paquets, failles, certificats. Sans règle, chaque équipe choisit la sienne, l'épingle (ou non) à sa façon, et personne ne peut répondre à « quelles images sont touchées par cette faille, et quand sont-elles corrigées ? ». Le catalogue `bibliotheque/` répond à cette question : **peu** d'images de base, **reconstruites chaque semaine**, **traçables** jusqu'à l'image amont.

## 2. Le catalogue

| Image MédiSphère | Amont (épinglé par empreinte dans le Dockerfile) | Usage | Étiquettes |
|---|---|---|---|
| `bibliotheque/debian` | `debian:trixie-slim` | base générique (outils, CI, binaires dynamiques) | `trixie-AAAAMMJJ` (immuable), `trixie` (mobile) |
| `bibliotheque/python` | `python:3.13-slim-trixie` | MédiAgenda, MédiNotif, MédiAnnuaire | `3.13-trixie-AAAAMMJJ`, `3.13-trixie` |
| `bibliotheque/php-apache` | `php:8.4-apache-trixie` | Legacy-RDV | `8.4-apache-trixie-AAAAMMJJ`, `8.4-apache-trixie` |

Hors catalogue mais **autorisées** (liste `images-autorisees.txt`) : `gcr.io/distroless/static-debian13` par empreinte (image finale des binaires statiques : aucun paquet à corriger, on suit l'amont par MR) ; `golang:1.26-trixie` par empreinte, **en étape de construction seulement** ; `ghcr.io/astral-sh/uv:0.12.x` en `COPY --from`. Toute autre image est refusée par la CI.

Chaque image du catalogue ajoute à son amont, et rien d'autre : les correctifs de sécurité disponibles le jour de la construction (`apt-get upgrade`), la racine de la PKI MédiSphère dans le magasin système, `ca-certificates` et `tzdata`. Elle reste en root (`USER 0` explicite) : c'est une base de **construction** ; l'image d'application fixe son propre utilisateur non root (norme `CNT-IMG-05`).

## 3. Cycle de vie

- **Hebdomadaire** : pipeline planifié « hebdomadaire » (lundi 04:00, Europe/Paris) sur `main` de `plateforme/images-base` ; chaque image reçoit une étiquette datée et l'étiquette mobile est déplacée. L'étiquette datée ne doit jamais être repoussée : **aujourd'hui, rien ne l'empêche** (le gabarit ne refuse que `latest`, `registry:3` accepte la réécriture) ; on ne relance donc pas un pipeline de publication le même jour sans nécessité, et l'immuabilité des étiquettes de Harbor (M13) lèvera cette limite.
- **Urgence** (faille critique) : lancement manuel du pipeline sur `main` ; **délai cible : 24 h** entre la publication du correctif Debian et l'image `bibliotheque/` corrigée, puis 5 jours ouvrés pour reconstruire les applications (leurs MR de montée d'empreinte).
- **Changement d'amont** (nouvelle empreinte, nouvelle version mineure de Python) : MR qui change l'`ARG AMONT`, avec la raison ; au M13, Renovate propose ces MR.
- **Retrait** : une image datée de plus de 90 jours n'est plus garantie ; les étiquettes datées sont conservées 180 jours dans le registre (ramasse-miettes de E15, puis règles de rétention de Harbor).

## 4. Ce que font les applications

- Elles référencent une étiquette **datée et son empreinte** (`…/bibliotheque/python:3.13-trixie-20261012@sha256:…`) : construction reproductible, montée de version par MR (une ligne).
- Une recette peut suivre l'étiquette **mobile** pour avoir les correctifs sans MR ; jamais une image de production.
- Le job `images-autorisees` (gabarit `plateforme/ci-templates`) échoue sur tout `FROM` hors liste, étapes de construction comprises, en affichant la liste.

## 5. Traçabilité

Étiquettes OCI de chaque image du catalogue : `org.opencontainers.image.base.name` (amont **avec** son empreinte), `revision` (commit de `plateforme/images-base`), `created` et `version` (date de construction), `source`. Depuis une image d'application : son `base.name` donne l'image `bibliotheque/` (étiquette datée et empreinte) ; les étiquettes de celle-ci donnent l'amont. `docker buildx imagetools inspect <image> --format '{{json .Image}}'` ou `skopeo inspect --config docker://<image>` les affichent.

## 6. Exceptions

Une image hors liste demande une MR sur `images-autorisees.txt` relue par Sophie Laurent, avec la raison et une **date de fin** en commentaire ; la revue trimestrielle retire les exceptions échues.

## 7. Déménagement vers Harbor (M13)

1. Créer le projet Harbor `bibliotheque` (privé, immuabilité des étiquettes datées, analyse Trivy à la poussée).
2. Copier les étiquettes datées en cours de validité : `skopeo sync --src docker --dest docker ctr01…:5000/bibliotheque registry.par1.medisphere.internal/bibliotheque` (identifiants des deux registres).
3. MR sur `plateforme/images-base` (variable `REGISTRE_BIBLIOTHEQUE`), sur `images-autorisees.txt` (préfixe) et sur `.hadolint.yaml` (`trustedRegistries`) ; puis les MR des applications (préfixe de `IMAGE_BASE`).
4. Après la dernière application migrée : retirer `ctr01…:5000/bibliotheque/*` de la liste.

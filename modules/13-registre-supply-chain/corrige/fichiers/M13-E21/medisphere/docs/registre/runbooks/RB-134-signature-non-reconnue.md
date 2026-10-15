# RB-134 — Signature non reconnue

| | |
|---|---|
| Quand | `cosign verify` (job `verifier-signature`, admission au M26) échoue sur une image qui « était signée » |
| Durée | 30 à 60 min |
| Règle | **on ne re-signe jamais pour faire passer un déploiement.** Re-signer, c'est attester à nouveau qu'une image vient de nous : il faut le prouver d'abord |

## 1. Lire le message

| Message | Sens |
|---|---|
| `no matching signatures` | des signatures existent, **aucune** ne se vérifie avec la clé donnée → mauvaise clé (rotation, clé de test, fichier remplacé) ou signature d'une autre clé |
| `no signatures found` | Cosign n'a rien trouvé **là où il cherche** → étiquette déplacée vers un autre digest, signature supprimée ou non copiée, client qui cherche au mauvais endroit (Cosign 2 : étiquette `sha256-<digest>.sig` ; Cosign 3 : référents OCI 1.1) |
| erreur TLS ou `unauthorized` | pas un problème de signature : RB-133 |

## 2. Établir les faits (sans rien modifier)

1. Digest actuel de l'étiquette : `crane digest` / `skopeo inspect --format '{{.Digest}}'`.
2. Digest **attendu** : celui produit par le pipeline (journal du job, rapport dotenv, attestation de provenance, `temoins.txt` pour les témoins).
3. Ce qui est attaché à chacun : `cosign tree <image>@<digest>`, onglet des accessoires de Harbor, `GET /v2/<dépôt>/referrers/<digest>`.
4. Clé : `sha256sum` de la clé publique utilisée contre `docs/registre/cosign.pub` (ou la clé de test des témoins).
5. Client : `cosign version` (ou l'image Cosign du gabarit) ; 3.x attendu.
6. Journal d'audit de Harbor (projet → *Logs*) : poussées, suppressions d'artefacts ou d'étiquettes, avec l'identité.

## 3. Corriger

| Cause | Correctif |
|---|---|
| Clé publique changée sans re-signature | revenir à la clé publiée ; une **rotation** se fait avec période de recouvrement (ADR-0130) |
| Étiquette déplacée vers un autre digest | replacer l'étiquette sur le digest signé (`POST …/artifacts/<digest>/tags`) ; enquêter sur l'auteur du déplacement ; immuabilité de l'étiquette |
| Signature supprimée ou non copiée | prouver que le digest est celui produit (provenance, journal du pipeline) puis re-signer **ce digest** ; sinon reconstruire et republier |
| Client Cosign 2 (paquet Debian) | Cosign 3.1 épinglé (rôle `outils_supply_chain`, image du gabarit par digest) |

## 4. Prévenir

Signature par digest seulement (gabarit) ; immuabilité `v*` ; copies d'images avec leurs référents (`oras cp -r`, réplication Harbor) et jamais `docker pull/tag/push` ; version de Cosign épinglée partout ; alerte sur les suppressions d'accessoires (journal d'audit, M22).

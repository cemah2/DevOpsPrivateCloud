# Politiques de confiance du registre

> Modèle de corrigé (M13-E14). Les messages sont ceux de Harbor 2.15.3 tels que le code source les
> formule ; remplace-les par ceux que tu as relevés.

## Par projet

| Projet | Privé | Signature Cosign exigée | Images vulnérables refusées | Analyse à la poussée | Immuabilité | Où c'est décrit |
|---|---|---|---|---|---|---|
| `medisphere` | oui | **oui** | **Critical et plus** | oui | `v*` | `plateforme/infra`, `registre/projets.tf` |
| `plateforme` | oui | non (prévu) | non | oui | `v*` | idem |
| `bibliotheque` | oui | non (prévu) | non | oui | `v*` | idem |
| `charts` | oui | non | non | — | `v*` | idem |
| caches | non (publics) | non | non | à la demande | — | `registre/caches.tf` |

## Ce que vérifient les politiques… et ce qu'elles ne vérifient pas

- **Signature exigée** : Harbor refuse de servir le manifeste d'une image de `medisphere` qui n'a **aucun** accessoire de signature Cosign. Il ne vérifie **ni la clé** ni l'identité du signataire : une image signée par n'importe quelle clé passe (essai de M13-E14, étape 5). La vérification de l'**auteur** est faite par le consommateur (`verification.yml`) et, à partir du module 26, par l'admission Kubernetes (Kyverno `verifyImages`).
- **Images vulnérables refusées** : Harbor refuse une image dont l'analyse signale au moins une vulnérabilité Critical, **et** une image non encore analysée ou dont l'analyse a échoué (on ne sert pas ce qu'on n'a pas regardé). Il ne sait rien des failles que la base de Trivy ne connaît pas encore (alerte de M13-E18).
- **Exemptions** (Harbor 2.15.3) : le scanner lit toujours les images refusées (droit `scanner-pull` porté par son jeton). Cosign, lui, **n'est plus exempté par défaut** (avis GHSA-wrw5-gmvj-gf23 : l'exemption reposait sur l'en-tête `User-Agent`, falsifiable) : sans réglage, la première signature d'une image de `medisphere` échoue en `412`. MédiSphère rétablit l'exemption **pour la seule signature exigée** (`CONTENT_TRUST_LEGACY_SIGNER_PULL_ENABLED=true` sur `core`, variable `harbor_cosign_lecture_avant_signature` du rôle `harbor`) : elle ne vaut que pour une identité qui a le droit de **pousser** dans le projet (robot de la CI, développeurs) — risque accepté, puisque ces identités peuvent de toute façon pousser. Aucune exemption pour la politique « images vulnérables » : la chaîne de livraison **attend la fin de l'analyse** de Harbor avant de signer.
- **Fenêtre** : entre la poussée et la signature (quelques secondes dans la chaîne), l'image existe mais est intirable : la chaîne de livraison ne la publie comme « disponible » qu'après la signature et la vérification.

## Messages de refus relevés

| Cas | Code HTTP | Message (début) |
|---|---|---|
| Non signée (y compris le manifeste de plateforme d'un index signé seul) | 412 | `PROJECTPOLICYVIOLATION` … `The image is not signed by cosign.` |
| Première signature sans l'exemption | 412 | même message, renvoyé à `cosign sign` |
| Vulnérable | 412 | `current image with <N> vulnerabilities cannot be pulled due to configured policy in 'Prevent images with vulnerability severity of "Critical" or higher from running.'` |
| Non analysée | 412 | `The image has not been scanned for vulnerabilities and cannot be pulled due to configured policy …` |

## Exceptions

1. Ticket `SEC-` qui nomme la CVE, l'image, la raison (pas de correctif, composant non atteignable…) et une date de fin (90 jours au plus).
2. MR sur `registre/projets.tf` : `cve_allowlist` du **projet** (jamais la liste du système), commentaire avec le ticket et la date ; relue par Sophie Laurent.
3. À la date de fin : retrait par MR, ou renouvellement argumenté.

## Vérification par le consommateur

Gabarit `plateforme/ci-templates`, `templates/verification.yml` : `cosign verify` puis `cosign verify-attestation --type spdxjson`, par digest, clé MédiSphère dont l'empreinte est épinglée, sans journal de transparence. Utilisé par le job `verifier-signature` des quatre applications ; il préfigure la vérification avant déploiement (M14) et l'admission (M26).

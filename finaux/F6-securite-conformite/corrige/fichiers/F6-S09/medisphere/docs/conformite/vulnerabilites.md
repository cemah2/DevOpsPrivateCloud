# Gestion des vulnérabilités et chiffrement des sauvegardes

> `plateforme/medisphere` — `docs/conformite/vulnerabilites.md` (F6-S09, SEC-3609, ferme ECA-3602 et
> ECA-3603). Propriétaire : RSSI (Sophie Laurent). Référentiels : ISO/IEC 27001:2022 A.8.8 (gestion des
> vulnérabilités techniques), A.8.13 (sauvegarde), A.8.24 (chiffrement), HDS v2 (activités 5 et 6).

## 1. Détection (déjà en place, M13)

- Harbor analyse chaque image (Trivy intégré) et **bloque au tirage** toute image avec une critique.
- La chaîne CI bloque les critiques **corrigeables** (`--ignore-unfixed`).
- Trivy Operator produit des `VulnerabilityReport` dans le cluster (couverture des charges déployées).

Ce qui manquait : l'**engagement de délai** de traitement et la **mesure du retard**.

## 2. Délais de traitement (ECA-3602)

Mesurés depuis la **première détection** (pas depuis la décision de traiter).

| Criticité | Délai | Si pas de correctif dans le délai |
|---|---|---|
| Critique | 7 jours | Exception datée obligatoire (RSSI), compensation écrite |
| Élevée | 30 jours | Exception datée |
| Moyenne | 90 jours | Suivi, pas d'exception requise |
| Basse | prochain cycle de l'image de base | — |

Justification : alignés sur les attentes HDS/ISO et sur ce qui est tenable quand le correctif dépend
d'un tiers (image de base). Des délais plus courts (48 h) seraient souvent intenables et masqueraient
le retard réel par des exceptions permanentes.

## 3. Exceptions datées et auto-expirantes

Une exception de vulnérabilité = une critique (ou élevée) acceptée temporairement, par exemple sans
correctif disponible.

- **Codée** dans la `cve_allowlist` du projet Harbor, dont la date d'expiration (`expires_at`, **une
  seule pour toute la liste**) est réglée sur l'échéance la plus proche des exceptions qu'elle contient :
  à cette date, Harbor cesse d'appliquer la liste entière, et les exceptions encore justifiées doivent
  être revalidées pour la rouvrir ;
- **Inscrite** au registre `docs/securite/durcissement/exceptions.md` (type **`EXC-V-nnn`**) : CVE,
  image, justification, risque résiduel, compensation, échéance (≤ 90 jours), valideur ;
- **Contrôlée** par `plateforme/politiques/outils/exceptions-vuln-echues.sh` (job de CI planifié) : il
  échoue si une exception est échue, si une date manque, ou si Harbor et le registre divergent — même
  logique que le pipeline des `PolicyException` du M26. Une exception échue ne s'applique donc plus
  (Harbor) **et** fait rougir la CI.

## 4. Suivi

Tableau Grafana `securite/vulnerabilites.json` (UID `f6-vulnerabilites`) : vulnérabilités ouvertes par
criticité et par âge, échéance de traitement, **retard** (en rouge au-delà du délai), alimenté par les
métriques de Trivy Operator et l'API de Harbor. Aucune saisie manuelle. C'est ce qu'on projette à la
revue hebdomadaire et ce qu'on montre à l'auditeur.

## 5. Chiffrement des sauvegardes et exports (ECA-3603)

« Côté serveur » : le stockage objet ne détient jamais le clair, **ni la clé**.

- **Velero, données des volumes** (`velero-k8s-par1` sur `s3-01`, Kopia) : Kopia chiffre toujours son
  dépôt, mais Velero l'initialise avec une phrase **par défaut**, identique partout et publiée : autant
  dire en clair. La phrase vient désormais d'OpenBao (`kv/plateforme/velero/depot`, propriété `phrase`),
  écrite dans le Secret `velero/velero-repo-credentials` (clé `repository-password`) par un
  `ExternalSecret` versionné dans `composants/velero/` de `plateforme/k8s`. La phrase étant globale et
  un dépôt existant gardant la sienne, les nouvelles sauvegardes vont sous un nouveau préfixe
  (`kopia-v2`) ; l'ancien emplacement reste en lecture seule (`s3-01-avant`) jusqu'à l'expiration des
  anciennes sauvegardes (14 jours).
- **Velero, manifestes** : l'archive des objets Kubernetes est déposée **en clair** par Velero ; les
  Secrets en sont exclus (`excludedResources: [secrets]`) puisqu'ESO les recrée depuis OpenBao (M25).
- **Exports bruts** (dumps, archives) : chiffrés par `age` dans le pipeline avant dépôt (clé publique
  dans le dépôt, clé privée dans `kv/plateforme/exports/age`, lisible par la RSSI et le rôle de
  restauration seulement).

### Restauration (éprouvée)

- Velero : restauration d'essai de `medidoc-dev` dans `wb-essais` depuis une sauvegarde faite **après**
  le changement de phrase — réussie le 2026-12-15 (P-SAV-03).
- Ancienne sauvegarde (avant le changement) : ESO suspendu sur `velero-repo-credentials` (`refreshInterval: 0`
  par MR), phrase par défaut remise,
  restauration, puis ESO réactivé — procédure jouée une fois, à ne plus utiliser après le 2026-12-29.
- Export `age` : déchiffrement d'un export d'essai avec la clé d'OpenBao — réussi le 2026-12-15.

Une sauvegarde qu'on ne sait pas déchiffrer n'est pas une sauvegarde : toute rotation de clé garde
l'ancienne clé le temps de la rétention des anciennes sauvegardes.

## 6. Revue

Mensuelle avec le registre des exceptions (M26) ; les échéances `EXC-V-nnn` du mois sont traitées
(prolonger avec justification, réduire, ou fermer). Le respect des délais est suivi comme un SLO
(« 95 % des critiques traitées dans le délai »).

# OpenBao 2.7 et HashiCorp Vault 2.2 : comparaison

> `docs/securite/secrets/comparatif-vault.md` — M25-E30 (PLAT-2630). Essai sur `bao-essai` (2251, détruite) le `<DATE>` : Vault **2.2.x** (binaire officiel, empreinte et signature vérifiées) contre la grappe OpenBao 2.7.1 et `kms01`. Chaque ligne « observé » a été faite ; « lu » renvoie à la documentation.

## 1. Installation et configuration de base

| Point | OpenBao 2.7.1 | Vault 2.2 | Source |
|---|---|---|---|
| Distribution | `.deb`/`.rpm` amont signés (pas de dépôt APT), images, EPEL (en retard) | zip, dépôts APT/RPM de HashiCorp, images | lu |
| Licence | MPL 2.0 (libre, fondation Linux / OpenSSF) | **BUSL 1.1** (concédant IBM) : usage interne permis, interdiction d'offrir un produit concurrent ; chaque version redevient MPL après quatre ans | lu (texte de la licence) |
| `disable_mlock` | **inconnu** (« unknown or unsupported field ») : mlock retiré | **obligatoire** (refus de démarrer sans) | observé |
| Audit | **déclaré** dans `openbao.hcl` ; l'API refuse (« use declarative, config-based audit device management ») | `vault audit enable` par l'API (fonctionne) | observé |
| Génération du jeton racine | `sys/generate-root-token` authentifié ; ancien point d'accès désactivé par défaut | `sys/generate-root` non authentifié (historique) | observé (OpenBao), lu (Vault) |
| Montages par défaut après `init` | `cubbyhole`, `identity`, `sys` | idem **plus** `agent-registry/` (nouveau en 2.x) | observé |
| Seal `transit` contre un **OpenBao** (`kms01`) | oui | **oui** (même API transit ; jeton par `VAULT_TOKEN`) | observé |

## 2. Fonctions

| Fonction | OpenBao 2.7 | Vault 2.2 communautaire | Vault Enterprise |
|---|---|---|---|
| Espaces de noms (*namespaces*) | **oui** (observé : `bao namespace create` sur 2.6.4 ; scellables par locataire depuis 2.6) | non : `vault namespace create` → « enterprise-only feature » (observé) | oui |
| Réplication de performance / DR entre grappes | non | non | oui |
| HSM / PKCS#11 (seal, clés gérées) | greffon KMS externe depuis 2.7 | non | oui |
| Plugin KMS v2 de Kubernetes (`vault-kube-kms`) | aucun | non | oui, **bêta** |
| *Control Groups* (approbation à plusieurs) | oui (2.7) | non | oui |
| Clés externes pour PKI et transit, ML-DSA | oui (2.7) | à vérifier | à vérifier |
| Instantanés Raft automatiques intégrés | non (minuterie, M25-E26) | non | oui (*snapshot agent*) |
| Montées de version automatisées (autopilot) | non décrites | non | oui |

## 3. Clients de MédiSphère

| Client | Avec OpenBao | Avec Vault 2.2 | Remarque |
|---|---|---|---|
| OpenTofu `hashicorp/vault` 5.13 | toutes nos ressources essayées (politiques, méthodes, rôles, `vault_raft_autopilot`, `vault_quota_rate_limit`, `vault_kv_secret_v2` avec métadonnées) | natif | `tofu plan` de `plateforme/secrets` contre `bao-essai` : `<RÉSULTAT>` ; les ressources `vault_audit` y passeraient, pas chez nous |
| ESO 2.13 (fournisseur `vault`) | testé par le projet avec OpenBao 2.2, classé *alpha* | natif | même API KV v2 et méthode Kubernetes |
| `community.hashi_vault` 7.1 | pas de mention, fonctionne sur nos usages (M25-E11) | natif | |
| Cosign `hashivault://` | à vérifier (M25-E20) | natif | variables `VAULT_ADDR`/`VAULT_TOKEN` dans les deux cas |
| CLI | `bao` (variables `BAO_*`) | `vault` (variables `VAULT_*`) | scripts à adapter (noms de variables, de binaire) |

## 4. Migration

- **Instantané OpenBao → Vault** (copie d'essai) : `vault operator raft snapshot restore -force` **accepte** l'instantané, le nœud se descelle (même clé de transit), les anciens jetons existent… mais le montage `kv/` **disparaît** de la table des montages (observé : `vault secrets list` ne montre que `cubbyhole`, `identity`, `sys`, `agent-registry`) : les deux produits n'enregistrent plus leurs montages de la même façon. **Il n'y a pas de passage par instantané.**
- Dans les deux sens, la seule voie sûre est **applicative** : recréer la configuration (OpenTofu : le fournisseur est le même), recopier les secrets KV par l'API, régénérer ce qui est dynamique (identifiants, certificats), réinscrire les identités (OIDC, JWT, Kubernetes). Coût estimé : `<JOURS>` jours de préparation, une fenêtre de bascule par consommateur.

## 5. Recommandation pour l'ADR-0250

Rester sur OpenBao : licence libre compatible avec la souveraineté exigée par la direction, espaces de noms et contrôles à plusieurs **sans** licence commerciale, mêmes clients et même fournisseur OpenTofu. Ce que Vault Enterprise apporterait (réplication vers PAR2, HSM intégré, instantanés automatiques) se compense chez nous par des instantanés planifiés (E26), un `kms01` sauvegardé et la grappe indépendante de PAR2 (F5). Risques à suivre : rythme de publication et taille de la communauté d'OpenBao, divergence croissante de l'API (audit, `generate-root`) qui rendra un retour vers Vault plus coûteux chaque année.

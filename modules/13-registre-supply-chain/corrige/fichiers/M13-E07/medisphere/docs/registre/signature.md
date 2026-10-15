# Signature des images MédiSphère

> SEC-1407 (M13-E07). Outil : Cosign 3.1. Propriétaire de la clé : équipe Plateforme ; validation des changements : RSSI.

## La clé

| Élément | Où |
|---|---|
| Clé publique | `docs/registre/cosign.pub` (ce dépôt) — **la seule** à utiliser pour vérifier |
| Empreinte de la clé publique | `sha256sum docs/registre/cosign.pub` → `<EMPREINTE-CLE-PUBLIQUE>` (à recopier dans chaque ADR et procédure qui la cite) |
| Clé privée | `plateforme/ansible`, `secrets/cosign/cosign.key`, fichier chiffré Vault `critique` |
| Phrase de passe | `vault_cosign_mdp` (Vault `critique`) |
| Copies CI | `COSIGN_PRIVATE_KEY` (fichier, protégée), `COSIGN_PASSWORD` (protégée, masquée) — groupes `mediagenda`, `medidoc`, `medinotif`, `legacy` |
| Algorithme | ECDSA P-256 (défaut de `cosign generate-key-pair`) |

## Sans journal de transparence

Le journal public de Sigstore (Rekor) publierait le nom et l'empreinte de chaque image signée. MédiSphère signe avec la configuration `docs/registre/signing-config.json` qui ne déclare **aucun service** (ni CA Fulcio, ni Rekor, ni horodatage) :

```
cosign sign   --key <clé> --signing-config docs/registre/signing-config.json <image>@sha256:<empreinte>
cosign verify --key docs/registre/cosign.pub --insecure-ignore-tlog=true <image>@sha256:<empreinte>
```

⚠️ Sans `--signing-config`, Cosign 3 utilise la configuration publique de Sigstore et **envoie l'entrée au journal public sans confirmation**. Contrôle : dans le bundle stocké (référent de type `application/vnd.dev.sigstore.bundle.v0.3+json`), `verificationMaterial.tlogEntries` doit être vide. L'ancienne option `--tlog-upload=false` est dépréciée et refusée dès qu'une configuration de signature est utilisée.

Conséquence assumée : sans journal ni horodatage signé, rien ne prouve **quand** une signature a été faite. Une signature produite avec une clé volée avant sa révocation est indiscernable d'une signature légitime : la révocation passe par le **retrait de la clé publique** et la re-signature de tout ce qui doit rester valide.

## Règles

1. On signe une **empreinte**, jamais une étiquette (Cosign avertit si on lui donne une étiquette ; l'outil `signer-image.sh` résout l'étiquette une fois et signe l'empreinte).
2. Seule la CI signe en routine (chaîne de livraison, M13-E09). Une signature à la main (`adm01`, `outils/signer-image.sh`) est un acte exceptionnel, tracé dans `docs/socle/journal/`.
3. On vérifie avec `cosign.pub` du dépôt, pas avec une copie locale.

## Vérifier une image

```
admin@adm01:~$ IMG=registry.par1.medisphere.internal/medisphere/mediagenda-api
admin@adm01:~$ D=$(skopeo inspect --format '{{.Digest}}' docker://$IMG:v1.4.0)
admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true $IMG@$D
admin@adm01:~$ cosign tree $IMG@$D          # signatures et attestations rattachées
```

## Rotation (tous les ans, ou au départ d'une personne qui a eu accès à la clé)

1. Générer une nouvelle paire (procédure M13-E07, en mémoire), la chiffrer en Vault `critique` sous un nouveau nom (`cosign-2027.key`).
2. Publier **les deux** clés publiques pendant la transition (`cosign.pub` + `cosign-2027.pub`) ; les vérificateurs (CI, Harbor au palier 3, Kyverno au M26) acceptent l'une ou l'autre.
3. Basculer les variables de CI ; re-signer les versions encore déployées avec la nouvelle clé.
4. Retirer l'ancienne clé publique, puis l'ancienne clé privée du Vault. Registre des secrets à jour.

## Révocation (clé compromise)

1. Retirer **immédiatement** `cosign.pub` du dépôt et des vérificateurs ; bloquer les déploiements (rien ne se vérifie plus).
2. Faire tourner `COSIGN_PRIVATE_KEY` et `COSIGN_PASSWORD`, et tous les secrets exposés au même endroit (variables CI du groupe, jeton du robot).
3. Nouvelle paire ; re-signer les images **reconstruites depuis le code** (ne pas re-signer une image publiée pendant la période de compromission sans l'avoir reconstruite et comparée).
4. Post-mortem dans `docs/socle/post-mortems/`.

## Et le *keyless* ?

La signature sans clé remplace la clé longue durée par un certificat de quelques minutes, délivré par une CA (Fulcio) contre un jeton OIDC qui décrit **l'identité du signataire** (pour une CI : le projet, la branche, le pipeline), et inscrit chaque signature dans un journal (Rekor) qui sert d'horodatage et d'audit. Plus de clé à voler, des politiques par identité (« signé par le pipeline de `mediagenda/api` sur `main` »).

Pour MédiSphère, il faudrait des **Fulcio et Rekor privés** (projets Sigstore auto-hébergeables, avec leur propre racine TUF, dont il faut assurer la sécurité), et l'**émetteur OIDC de GitLab** (jetons `id_tokens` des jobs) comme source d'identité. Gain : identités fines et traçabilité horodatée ; coût : trois services critiques de plus à exploiter, superviser et sauvegarder. À réévaluer après le module 24 (identité) et le module 25 (secrets) : ADR-0130.

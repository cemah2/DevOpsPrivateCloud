# Module 13 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M13-E25 — Mini-projet : registre MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail**, les points de contrôle de chaque étape, la préparation des quatre démonstrations et la **grille de revue**. Les fichiers de référence sont ceux des exercices du module ; nouveaux : [`architecture.md`](fichiers/M13-E25/medisphere/docs/registre/architecture.md) (modèle) et la [section containerd de `caches.md`](fichiers/M13-E25/medisphere/docs/registre/caches-containerd.md.extrait).

**Points non testés en conditions réelles** : la commande de traçabilité (démonstration de Karim) lit la provenance par l'attestation Cosign `slsaprovenance1` que la chaîne extrait de l'archive (E09) ; lire directement le manifeste d'attestation de BuildKit **dans Harbor** (annoté `attestation-manifest`, couche `in-toto.io/predicate-type: https://slsa.dev/provenance/v1`, `oras blob fetch`, E23) est refusé sous les politiques de `medisphere` : ce manifeste n'est ni signé ni analysé (code de Harbor 2.15.3 : `contentrust.go`, `vulnerable.go`) ; les noms exacts des champs sont à vérifier sur ta sortie (`provenance.json`, artefact du job `sc:signature`). Le comportement de repli de `hosts.toml` (champ `server`) est à vérifier sur containerd 2.3 au module 14.

**Solution**

*Plan de travail recommandé* (dans cet ordre : on retire le provisoire **après** avoir prouvé qu'on sait s'en passer)

1. **État des lieux** (30 min) : `lab/bin/check 13 25`, puis les contrôles détaillés rouges (`13 13` à `13 23`) et `lab/bin/check 12 46`. Liste des restes : `reg02` et ses états (`m13-registre`, dossier `envs/m13` ; `registre-reg02`), endpoint et politique sur `reg01`, flux temporaires, témoins (`wb-sonde*`, fichiers de `runner02`), utilisateur `wb-pannes` et `~/.config/workbook/harbor-pannes.env`, dépôts `essai-*`, secrets de `reg02` en Vault, jeton PBS `wb-restore@pbs!reg02`.
2. **Les quatre images** (3 à 5 h) : appliquer les gabarits `templates/supply-chain.yml` (E09) et `templates/verification.yml` (E14) à `medidoc/medidoc`, `medinotif/worker` et `legacy/legacy-rdv` ; images de base de `bibliotheque` ou des caches, **par digest** (Renovate tient les digests à jour) ; publier une version `vX.Y.Z` de chacune par semantic-release. Contrôle :
   ```
   admin@adm01:~$ for a in mediagenda-api medidoc medinotif legacy-rdv; do
       d=$(skopeo inspect --format '{{.Digest}}' docker://registry.par1.medisphere.internal/medisphere/$a:<vX.Y.Z>)
       cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true registry.par1.medisphere.internal/medisphere/$a@$d >/dev/null \
       && cosign verify-attestation --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true --type spdxjson \
            registry.par1.medisphere.internal/medisphere/$a@$d >/dev/null && echo "$a OK"; done
   ```
   Legacy-RDV (PHP, image Apache volumineuse) est souvent celle qui échoue sur Trivy « Critical corrigeable » : on met à jour l'image de base, on ne pose pas d'exception sans ticket.
3. **Politiques et rétention** (30 min) : `medisphere` (E10, E14) ; règle de rétention attachée ; exceptions éventuelles datées.
4. **Caches et `runner02`** (1 h) : aucune image de job ni `FROM` hors de Harbor (`grep -R "image:\|FROM" ` sur les projets, gabarits inclus) ; section containerd de `caches.md` (extrait fourni) ; robot `k8s-pull` en Vault ; flux VLAN 40 → `reg01:443` (déjà posé en E02).
5. **Renovate** (30 min) : pipeline planifié vert, MR ouvertes sur les quatre applications, fusion automatique limitée aux correctifs (E11) ; retirer la règle temporaire `allowedVersions` de E18 si le correctif de l'éditeur est sorti (sinon la garder et la dater).
6. **Exploitation** (1 h 30) : sauvegarde nocturne vérifiée ; **test de restauration pour la livraison** sur une VM jetable (reprendre `envs/m13` avec `reg02` **avant** de la détruire : c'est le moment) ; Harbor dans la dernière version corrective (E16) ; `ms-verif-registre` vert ; ramasse-miettes planifié.
7. **Retirer le provisoire** (1 h), dans cet ordre :
   1. sur `reg01` : vider `TF_VAR_reg02_robot_secret` → `tofu apply` de `registre` supprime la politique **puis** l'endpoint ;
   2. `tofu destroy` de `registre-reg02`, puis de `envs/m13` (VM, NetBox, DNS) ;
   3. retirer la définition `REG02` et les quatre règles temporaires (E13, E15) de `pare_feu.yml`, appliquer aux deux passerelles, mettre à jour `matrice-flux.md` ;
   4. supprimer de Vault les secrets `vault_reg02_*`, `vault_pbs_jeton_restauration_reg02`, les `host_vars/reg02/` ; sur `pbs01`, `proxmox-backup-manager user delete-token wb-restore@pbs reg02` ;
   5. témoins : projets `wb-sonde` et `wb-sonde-public` (dépôts compris), robots `wb-sonde-tirage` et `wb-sonde-ci` ; sur `runner02`, `/etc/workbook/sonde-registre/`, `/var/lib/workbook/temoins-m13/`, `/usr/local/sbin/wb-sonde-registre` ;
   6. utilisateur `wb-pannes` de Harbor, puis `rm ~/.config/workbook/harbor-pannes.env` ; registre des secrets mis à jour (exception close) ;
   7. `ls ~/.local/state/workbook/pannes-actives/` : aucune entrée `M13-*`.
8. **Documentation** (2 h) : `architecture.md`, `politiques.md`, `replication.md` (avec « ce qui remplace `reg02` »), `sauvegarde.md`, `caches.md`, ADR-0130, RB-130 à RB-135, `alertes/CS-2026-0412.md`, inventaire NetBox, matrice des flux, registre des secrets (emplacements : admin de Harbor, mot de passe de la base, robots, clé Cosign et sa phrase de passe, clé de chiffrement PBS).
9. **Livraison** : MR fusionnées, pipelines de `main` verts, étiquette `registre-v1` sur `plateforme/medisphere`.

*Les démonstrations* (à répéter **avant** la revue)

| Démonstration | Préparation | Attendu |
|---|---|---|
| Sophie : tirage d'une image non signée | une image poussée dans `medisphere/essai-revue:non-signee` juste avant (et supprimée juste après) | `412`, message de la politique Cosign ; puis la même image vérifiée par `verification.yml` : refus par clé |
| Julien : correctif jusqu'à l'image signée | une MR prête sur `mediagenda/api` (commit `fix:`) | pipeline : construction, Trivy, SBOM, poussée, signature, attestations, `verifier-signature` ; nouvelle version `vX.Y.Z+1` signée dans Harbor |
| Nadia : arrêt de Harbor | `sudo systemctl stop harbor` sur `reg01` pendant la présentation | `ms-verif-registre` en KO au passage suivant (≤ 5 min), `ms-alerte` reçue ; `systemctl start harbor`, retour au vert ; les jobs échoués relancés |
| Karim : traçabilité d'une image en 5 min | une commande prête (ci-dessous) | digest, signature vérifiée, composants principaux, provenance (dépôt, commit, pipeline), analyse |

Commande de traçabilité (à mettre dans `plateforme/outils`, par exemple `outils/tracer-image.sh`) :

```
admin@adm01:~$ I=registry.par1.medisphere.internal/medisphere/medidoc; T=<vX.Y.Z>; K=~/medisphere/docs/registre/cosign.pub
admin@adm01:~$ D=$(skopeo inspect --format '{{.Digest}}' docker://$I:$T); echo "digest : $D"
admin@adm01:~$ cosign verify --key $K --insecure-ignore-tlog=true $I@$D >/dev/null && echo "signature : vérifiée (clé MédiSphère)"
admin@adm01:~$ cosign verify-attestation --key $K --insecure-ignore-tlog=true --type spdxjson $I@$D \
    | jq -r '.payload | @base64d | fromjson | .predicate.packages[] | "\(.name) \(.versionInfo)"' | sort | head -20
admin@adm01:~$ cosign verify-attestation --key $K --insecure-ignore-tlog=true --type slsaprovenance1 $I@$D \
    | jq '.payload | @base64d | fromjson | .predicate | {source: .buildDefinition.externalParameters.configSource, args: .buildDefinition.externalParameters.request.args, run: .runDetails.metadata}'
admin@adm01:~$ curl -s -u "$U" "https://registry.par1.medisphere.internal/api/v2.0/projects/medisphere/repositories/medidoc/artifacts/$D?with_scan_overview=true" \
    | jq '.scan_overview | to_entries[0].value | {severity, summary: .summary.summary}'
```

**Grille de revue**

| Domaine | Attendu | Points |
|---|---|---|
| Contrôle global | `lab/bin/check 13 25` entièrement vert | 4 |
| Images | quatre applications signées, SBOM attestée, analyse sans Critical, bases par digest depuis Harbor | 3 |
| Politique de confiance | ADR-0130 lisible par un auditeur ; vérification par clé chez le consommateur ; limites dites | 3 |
| Rien de provisoire | `reg02`, témoins, `wb-pannes`, flux temporaires, secrets d'essai retirés dans le bon ordre, par le code | 2 |
| Exploitation | sauvegarde et restauration testée pour la livraison (RTO, RPO), sonde, version à jour, runbooks | 3 |
| Préparation du M14 | `hosts.toml` documenté, `k8s-pull`, flux VLAN 40 | 1 |
| Démonstrations | les quatre passent, et tu sais expliquer ce qui se passe à chaque étape | 3 |
| Honnêteté | ce qui n'est pas redondant et ce qui reste à faire (M14, M24, M25, M26) | 1 |

16 points et plus : livrable. Un rouge au contrôle global, une démonstration ratée ou un secret en clair : non livrable, quelle que soit la note.

**Explications**

Le mini-projet n'ajoute presque rien de neuf : il oblige à rendre **cohérent** ce qui a été construit exercice par exercice, et à retirer ce qui ne servait qu'à apprendre. L'ordre de retrait compte : un objet qui en référence un autre (politique → endpoint → VM) se retire d'abord, sinon la sonde (ou la réplication planifiée) échoue chaque nuit. La démonstration de Karim est le test le plus juste de la supply chain : si l'on ne retrouve pas en cinq minutes d'où vient une image, la chaîne ne sert pas.

**Pièges classiques**
- Détruire la VM `reg02` avant d'avoir retiré l'endpoint : réplication en échec chaque nuit.
- Oublier les secrets d'essai en Vault et le jeton PBS de lecture : un accès aux sauvegardes de production reste ouvert.
- Poser une exception de CVE pour faire passer Legacy-RDV « le temps de la revue ».
- Laisser `wb-pannes` « au cas où » : un compte administrateur local de plus, juste avant l'arrivée d'OIDC.

**En production chez MédiSphère**
La même recette, rejouée à chaque grande évolution du registre (mineure de Harbor, changement de clé, PAR2) ; le contrôle global devient un pipeline planifié de `plateforme/outils` dont l'échec ouvre un ticket.

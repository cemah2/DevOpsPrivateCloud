# RB-254 — Rotation des secrets

> `docs/securite/secrets/runbooks/RB-254-rotation.md` — M25-E33 (SEC-2633). Politique : `politique-rotation.md`. Fuite : RB-250 d'abord.

## 1. Le pipeline planifié a échoué

1. Ouvrir le pipeline planifié de `plateforme/secrets` (CI/CD → Pipelines, source *schedule*), lire le job en échec.
2. `verification:ages` : l'artefact `rapport-ages.tsv` dit quoi. `SANS-METADONNEES` → poser les métadonnées : `bao kv metadata patch -mount=kv -custom-metadata=proprietaire=<ÉQUIPE> -custom-metadata=rotation=<PÉRIODE>h <CHEMIN>`. `EN-RETARD` → §2 pour ce type.
3. `rotation:*` : la rotation a échoué **avant** l'écriture dans le coffre → rien n'a changé, relancer après correction ; **après** → le coffre a la nouvelle valeur, l'ancien secret est toujours valable (chevauchement) : terminer à la main (§2) avant le job de vérification.
4. `verification:consommateurs` : un consommateur n'a pas repris le nouveau secret → **ne pas** invalider l'ancien ; voir l'`ExternalSecret` (`kubectl -n <ESPACE> get externalsecret <NOM> -o yaml` : `status.refreshTime`, conditions), forcer un rafraîchissement (annotation `force-sync=$(date +%s)`), vérifier Reloader.

## 2. Rotation à la main, par type (quand l'automate est en panne)

Toujours : session `bao login -method=oidc` ; aucune valeur à l'écran (tubes, `clé=-`).

- **Client Keycloak** : depuis le clone de `plateforme/secrets`, avec un jeton personnel portant `kv/data/plateforme/*` : `outils/rotation/client-keycloak.sh <CLIENT> <CHEMIN>` ; attendre la reprise (ESO 5 min, Reloader) ; `outils/rotation/client-keycloak-verifier.sh <CLIENT> <CHEMIN> <URL-SANTÉ>`.
- **Jeton GitLab** : `outils/rotation/jeton-gitlab.sh <CHEMIN>` puis, après reprise, `jeton-gitlab-revoquer.sh <CHEMIN>`.
- **Racine d'une connexion de base** : `bao write -f db-mediagenda/rotate-root/<CONNEXION>`.
- **Secret KV d'application** : écrire la nouvelle valeur dans la **source** (le service lui-même accepte d'abord l'ancien et le nouveau quand il le peut), puis `bao kv patch`, puis attendre ESO et Reloader, puis retirer l'ancien côté source.
- **Clé de transit** : `bao write -f transit/keys/<CLÉ>/rotate` ; réécrire les données (`transit/rewrap/<CLÉ>`, SOPS : `sops updatekeys` / `sops -r`) ; seulement ensuite `min_decryption_version`.
- **Trousseau** : cérémonie (`procedure-jeton-racine.md`), `bao operator rotate`, révocation du jeton.

## 3. Contrôle de non-coupure

Pendant toute rotation d'un secret consommé : tableau du consommateur (erreurs 5xx), sonde du témoin `mon01`, journaux de connexion (Keycloak : `CODE_TO_TOKEN_ERROR` / `invalid_client_credentials`).

## 4. Retour arrière

Le coffre garde les versions (`max_versions` 10) : `bao kv rollback -mount=kv -version=<N-1> <CHEMIN>` remet l'ancienne valeur **tant que la source l'accepte encore** (avant invalidation de l'ancien secret Keycloak ou révocation de l'ancien jeton GitLab). Après : nouvelle rotation, pas de retour.

# M25-E14 — Banc d'essai (modèle ; aucun mot de passe)

Base jetable : Cluster CNPG `pg-essai` d'une instance dans `wb-essais` (modèle du M16-E25), connexion `essai-wb` du moteur `db-mediagenda/`, rôle `essai` (TTL 5 min). Connexion d'essai par un `kubectl port-forward` depuis `adm01` ; supprimés en fin d'essai.

| Heure | Action | Observation |
|---|---|---|
| HH:MM | `bao read db-mediagenda/creds/essai` | bail `db-mediagenda/creds/essai/<id>`, durée 300 s ; compte `v-oidc-<moi>-essai-…` |
| HH:MM | `psql` avec ce compte, `SELECT now();` | connecté |
| HH:MM | `bao lease revoke <bail>` pendant la session ouverte | dans la session : `ERROR: permission denied for table …` puis `ERROR: invalid role OID: …` ; nouvelle connexion : `password authentication failed` |
| HH:MM | `SELECT rolname FROM pg_roles WHERE rolname LIKE 'v-%'` (superutilisateur) | le compte a disparu (`DROP ROLE` de la révocation) |

Conclusion : la révocation d'un bail **coupe** les sessions en cours de ce compte (le rôle n'existe plus) ; une application doit avoir changé d'identifiant avant la fin du bail, ou savoir se reconnecter avec un nouveau.

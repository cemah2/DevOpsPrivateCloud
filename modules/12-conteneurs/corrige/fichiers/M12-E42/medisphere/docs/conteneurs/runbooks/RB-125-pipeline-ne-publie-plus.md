# RB-125 — Le pipeline ne publie plus l'image

| | |
|---|---|
| **Déclencheur** | job de construction ou de publication en échec sur `runner02`, sans modification du `.gitlab-ci.yml` |
| **Chaîne** | GitLab → `runner02` (exécuteur `docker`, sans privilège) → constructeur sans démon (BuildKit sans privilège ou Buildah, gabarit `image.yml`) → registre de travail `ctr01:5000` (Harbor `reg01` à partir du M13) |
| **Interdits** | `privileged = true` ; `--insecure-registry`, `--tls-verify=false` ou désactivation de la vérification TLS ; secret en clair dans un job ou un journal |

## 1. Situer l'étape dans le journal du job

| Message | Étape | Aller à |
|---|---|---|
| `failed to pull image … with specified policies` / `pull access denied` | exécuteur : image du job | 2a |
| erreurs `rootlesskit`, `operation not permitted`, `failed to mount`, `unshare` au démarrage du constructeur | exécuteur : options de sécurité | 2b |
| erreur de construction (étape `RUN`, `COPY`) | construction | RB-120, M12-E38 |
| `401 Unauthorized`, `failed to authorize`, `denied` | authentification au registre | 2c |
| `x509: certificate signed by unknown authority`, `certificate has expired` | confiance TLS | 2d |

## 2. Reproduire hors CI

**a. Image du job** — sur `runner02` : `sudo grep -n pull_policy /etc/gitlab-runner/config.toml`, `sudo docker pull <image du job>`. Politique attendue : celle du rôle `gitlab_runner` (jamais `["never"]` seule tant qu'aucun cache de registre n'existe).

**b. Options de sécurité** — `sudo grep -n -E 'privileged|security_opt|cap_add|devices' /etc/gitlab-runner/config.toml` : comparer à l'ADR-0120 (exceptions `seccomp`/`apparmor` `unconfined` pour la construction sans démon, **aucune** capacité ajoutée, `privileged = false`). Dates : `sudo ls -l --time-style=full-iso /etc/gitlab-runner/` ; journal : `sudo journalctl -u gitlab-runner --since today`.

**c. Authentification** — depuis `adm01`, sans exposer le mot de passe :
```
curl -s -o /dev/null -w '%{http_code}\n' --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://ctr01.par1.medisphere.internal:5000/v2/          # 401 attendu
curl -s -o /dev/null -w '%{http_code}\n' -K ~/.config/workbook/registre-ci.curl https://ctr01.par1.medisphere.internal:5000/v2/   # 200 attendu
```
Si le compte `ci` est refusé : **rotation complète** (nouveau mot de passe, entrée htpasswd par le rôle du registre, redémarrage du registre si nécessaire, variable protégée et masquée des projets, entrée du registre des secrets), jamais d'un seul côté.

**d. TLS** — `openssl s_client -connect ctr01.par1.medisphere.internal:5000 -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt </dev/null | grep -E 'issuer=|Verify return'` ; `openssl x509 -noout -dates`. Rétablir un certificat ACME de step-ca et vérifier son renouvellement automatique.

## 3. Corriger, relancer, reporter

Correction dans la source (rôle `gitlab_runner`, rôle du registre, variables de CI), pipeline relancé jusqu'au vert, entrée dans le journal de diagnostic. Toute exception de sécurité modifiée passe par une MR relue par la RSSI.

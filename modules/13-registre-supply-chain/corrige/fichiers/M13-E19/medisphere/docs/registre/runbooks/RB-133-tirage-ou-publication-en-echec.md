# RB-133 — Tirage ou publication en échec

| | |
|---|---|
| Quand | un job, un hôte ou (à partir du M14) un nœud n'arrive pas à tirer ou à pousser une image de `registry.par1.medisphere.internal` |
| Durée | 15 à 45 min |
| Prérequis | accès `adm01`, `runner02`, `reg01` ; identité de test en lecture (ton compte) |
| Règle | ne jamais élargir un droit, rendre un projet public, désactiver TLS ou retirer une politique pour « débloquer » |

## 1. Reproduire et situer

1. Depuis l'hôte qui échoue **et** depuis `adm01` : `skopeo inspect docker://registry.par1.medisphere.internal/<projet>/<dépôt>:<étiquette>` (avec l'identité du job, puis la tienne). Même résultat ? Non → le client ou l'identité ; oui → le registre.
2. `curl -s https://registry.par1.medisphere.internal/api/v2.0/health` : un composant en défaut → RB-135.

## 2. Lire le message → l'étage

| Message (Docker, Skopeo, containerd) | Étage | Vérifier |
|---|---|---|
| `x509: certificate signed by unknown authority` | client TLS | racine MédiSphère dans le magasin (`/usr/local/share/ca-certificates/`, `update-ca-certificates`), `/etc/docker/certs.d/`, démon redémarré après changement |
| `x509: certificate has expired or is not yet valid` | client TLS **ou horloge** | `openssl s_client … | openssl x509 -noout -dates` ; `timedatectl`, `chronyc tracking` sur le client |
| `unauthorized: authentication required` / `unauthorized` au jeton | service de jetons, identité | robot actif ? expiré ? (Harbor → Robots) ; identifiants à jour (variable CI, `config.json`) |
| `unauthorized to access repository …, action: pull` | droits ou visibilité | projet public/privé, membres, permissions du robot sur **ce** projet |
| `denied: requested access to the resource is denied` à la poussée | droits | le robot a-t-il `repository:push` sur ce projet ? |
| `… will exceed the configured upper limit of …` | quota | quota du projet (Résumé), occupation, artefacts sans étiquette |
| `… configured as immutable` / `cannot be overwritten` | immuabilité | règles du projet : la règle vise-t-elle vraiment cette étiquette ? une **version** ne se réécrit pas (on publie la suivante) |
| `412 Precondition Failed` / `PROJECTPOLICYVIOLATION` | politique de projet | signature présente ? analyse terminée ? vulnérabilité Critical ? (RB-134, `politiques.md`) |
| `manifest unknown` sur une image publique jamais tirée, les autres passent | cache (amont) | endpoint du cache : état, identifiants, `/var/log/harbor/core.log` |

## 3. Rejouer l'échange à la main

```
admin@adm01:~$ curl -sI https://registry.par1.medisphere.internal/v2/ | grep -i www-authenticate
admin@adm01:~$ curl -s -u '<IDENTITÉ>' 'https://registry.par1.medisphere.internal/service/token?service=harbor-registry&scope=repository:<projet>/<dépôt>:pull' \
    | jq -r .token | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq .access
```

`access` vide = identité reconnue mais sans droit sur cette portée ; code 401 = identité refusée.

## 4. Réparer à la racine

Par le code de configuration de Harbor (`plateforme/infra`, état `registre`) pour un objet de production ; par l'API ou l'interface pour un témoin, en notant l'écart. Puis vérifier depuis l'hôte d'origine et clore le ticket avec la cause.

## 5. Prévenir

Rotation des robots planifiée (registre des secrets, J-30) ; sonde `ms-verif-registre` ; `chrony` supervisé ; racine MédiSphère déployée par le rôle `ca_lab` et non à la main.

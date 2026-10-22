<!-- Sections à ajouter à RB-190 « Un pipeline reste en attente » (M19-E22), après M19-E35. -->

## Causes rencontrées en panne (M19-E35)

| Ce que je vois | Cause | Preuve | Correctif |
|---|---|---|---|
| Job `pending`, message « stuck… any of these tags: k8s » ; runner `online` | Aucun runner ne porte **toutes** les étiquettes du job (étiquettes du runner modifiées) | `GET /runners/all` puis `GET /runners/:id` → `tag_list`, `maintenance_note` | Rétablir `k8s,kubernetes` par le script de création du runner (source de vérité) ; vider la note |
| Job `pending`, runner `online` | Runner suspendu (`paused: true`) | `GET /runners/:id` → `paused`, `maintenance_note` | `PUT /runners/:id paused=false` ; toute pause a une échéance écrite |
| Job `running` puis `prepare environment: … forbidden: exceeded quota` | Quota de `ci-jobs` trop bas ou faux (unité) | `kubectl -n ci-jobs describe resourcequota` ; événements de l'espace | `task appliquer` sur `plateforme/k8s/espaces/ci-jobs/` après `kubectl diff` |
| Seul un job d'une branche quelconque attend ; il demande `protege` | Le runner protégé (`ref_protected`) ne prend que les références protégées : **voulu** | `GET /runners/:id` → `access_level` ; `GET /projects/:id/protected_branches` | Rien côté plateforme : expliquer ; le job change d'étiquette ou passe sur une référence protégée prévue pour cela. Ne jamais protéger une branche de travail pour lui donner les secrets |

## Commandes

```
GITLAB=https://git01.par1.medisphere.internal
gl() { curl -sS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-admin.token)") "$GITLAB/api/v4/$1" "${@:2}"; }
gl "runners/all?per_page=100" | jq -r '.[] | [.id, .description, .status, .paused] | @tsv'
gl "runners/<id>" | jq '{tag_list, run_untagged, access_level, maintenance_note, contacted_at}'
kubectl -n ci-jobs get events --sort-by=.lastTimestamp | tail -n 20
```

## Prévention

- Alerte sur l'âge du plus vieux job en attente par étiquette (M21).
- Contrôle quotidien : runners suspendus depuis plus de 4 h, étiquettes différentes du code.

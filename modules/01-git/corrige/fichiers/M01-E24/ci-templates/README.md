# plateforme/ci-templates

Gabarits GitLab CI communs aux projets de l'équipe Plateforme (MédiSphère).

| Fichier | Rôle | Introduit |
|---|---|---|
| `templates/qualite.yml` | `workflow`, stages standard, jobs `pre-commit`, `commitlint`, `gitleaks` | M01-E24 |
| `templates/release.yml` | job `release` : semantic-release sur la branche par défaut | M01-E25 |
| `outils/release-tools/` | `package.json` + `package-lock.json` des outils Node du runner, script d'installation | M01-E24 |

## Utiliser les gabarits

Dans le `.gitlab-ci.yml` du projet :

```yaml
include:
  - project: plateforme/ci-templates
    ref: v1
    file:
      - templates/qualite.yml
      - templates/release.yml   # si le projet publie des versions (avec .releaserc.json)
```

`ref: v1` désigne la **branche `v1`** : elle suit la dernière version `1.x.y` publiée
(mise à jour automatiquement après chaque release, M01-E25). Un projet reçoit donc
les correctifs et les ajouts compatibles sans rien changer, et jamais une rupture :
une version majeure `2.0.0` publierait une branche `v2`, à adopter explicitement.
Pour figer complètement, utilise l'étiquette exacte (`ref: v1.4.2`) ou un SHA.

Le projet doit contenir :
- `.pre-commit-config.yaml` (référence : M01-E15) — sinon le job `pre-commit` n'est pas créé ;
- `commitlint.config.mjs` (référence : M01-E14) — sinon la configuration conventionnelle intégrée est utilisée ;
- `.releaserc.json` (référence : M01-E25) s'il inclut `release.yml` — sinon le job `release` n'est pas créé.

Réglages du projet attendus : `main` protégée, fusion par MR, « Pipelines must succeed »
activé et « Skipped pipelines are considered successful » désactivé.

## Runner requis

Étiquette `shell` (runner `runner01`, exécuteur shell) avec :
`git`, `pre-commit` 4.x, `gitleaks` 8.30.x, Node.js 24, et `/opt/release-tools`
installé depuis ce dépôt :

```
root@runner01:~# git clone https://git01.par1.medisphere.internal/plateforme/ci-templates.git /root/ci-templates
root@runner01:~# /root/ci-templates/outils/release-tools/installer-release-tools.sh
```

Le job `outils-a-jour` de ce projet échoue si le verrou versionné ici et celui
installé sur le runner divergent.

### Pourquoi `NODE_PATH`

commitlint cherche les configurations partagées (`extends`) à partir du dossier du
projet, puis dans le dossier global de npm : il ne trouve pas celles de
`/opt/release-tools`. Le job lui donne `NODE_PATH=/opt/release-tools/node_modules`,
pris en compte par la résolution CommonJS qu'il utilise. semantic-release, lui,
cherche ses extensions et ses *presets* d'abord à côté de lui-même : tant qu'ils sont
installés dans le même `node_modules`, il les trouve sans aide.

## Contribuer

MR obligatoire, Conventional Commits : un `fix:` publie un correctif, un `feat:` une
version mineure. **Pas de rupture sur `v1`** : un changement incompatible
(`feat!:` ou pied `BREAKING CHANGE:`) publie une version majeure et doit être
discuté avant (ADR).

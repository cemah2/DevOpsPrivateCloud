# Rôle `harbor`

Harbor (installateur **hors ligne**) sur Debian 13, avec Docker Engine 29 et Compose v5 du rôle
`docker_engine` (M12). Introduit en M13-E02 pour `reg01` ; réutilisé tel quel pour `reg02` (M13-E13).

## Ce que le rôle fait et ne fait pas

| Fait | Ne fait pas |
|---|---|
| `/data` sur le disque de données (XFS, par identifiant stable), Docker attend `/data` | créer des projets, robots, caches, politiques (état OpenTofu `registre`) |
| installateur téléchargé sur l'hôte, **vérifié par empreinte**, un dossier par version | vérifier la signature Sigstore de l'installateur (geste humain à l'épinglage, RB-130) |
| `harbor.yml` (600) depuis les clés du `harbor.yml.tmpl` de la version | modifier les fichiers générés par `prepare` |
| `install.sh --with-trivy` **une fois** ; ensuite `prepare` + redémarrage si `harbor.yml` change | monter de version sans `-e harbor_autoriser_changement_version=true` (RB-132) |
| `harbor.service`, script `harbor-recharger-certificat` pour `cert-renewer@harbor` | émettre le certificat (rôle `certificats_acme`, id `harbor`) |
| contrôle `/api/v2.0/health` et version de `harbor-core` | sauvegarder (M13-E15) |

## Ordre dans le playbook

`prerequis.yml` (seul) → `certificats_acme` → rôle complet. Le certificat doit exister avant la
première installation (prepare le copie dans `/data/secret/cert/`), le port 80 doit être libre à
l'émission (défi HTTP-01 : Harbor arrêté, `avant_emission: systemctl stop harbor.service`), et le
script de rechargement doit exister quand `certificats_acme` l'appelle.

## Variables principales

Voir `defaults/main.yml`. Secrets : `vault_harbor_admin_mdp`, `vault_harbor_db_mdp` (Vault `critique`,
`group_vars/role_registre/vault-critique.yml`).

## Limites connues

- `harbor_admin_password` n'agit qu'à la première installation : changer le mot de passe d'`admin`
  ensuite passe par l'API, puis par le Vault (sinon le Vault et Harbor divergent).
- Le pare-feu local `pare_feu_local` (M06-E30) n'est **pas** appliqué à `reg01` : son
  `flush ruleset` effacerait les règles que Docker écrit ; les ports publiés par Docker passent
  de toute façon par la chaîne `forward`, pas par `input`. Voir le corrigé de M13-E02.

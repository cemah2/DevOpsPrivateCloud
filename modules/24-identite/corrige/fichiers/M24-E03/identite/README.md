# plateforme/identite

Identité de MédiSphère : **qui** existe (annuaire FreeIPA de `ipa01`) et **comment** on se connecte (royaume `medisphere` de Keycloak sur `idp01`). Module 24 du workbook ; décisions : PLAN §4.12, ADR-0240 (M24-E31).

| Dossier | Contenu | Appliqué par |
|---|---|---|
| `annuaire/` | personnes, groupes, politique de mot de passe, comptes système, puis HBAC et sudo (M24-E19) | job manuel `annuaire:appliquer` de `main` (Ansible, `freeipa.ansible_freeipa`) |
| `tofu/` | royaume, fédération LDAP, portées, flux, clients, comptes de service (à partir de M24-E08) | jobs `plan` (MR) et `apply` manuel (`main`) d'OpenTofu |
| `outils/` | `vault-pass-client.sh` (copie de `plateforme/ansible`), puis outils de synchronisation et de revue d'accès | — |

## Règles

- **Rien à la main** dans FreeIPA ni dans le royaume `medisphere` : une arrivée, un départ, un client OIDC, c'est une MR ici (exceptions : exercices de découverte du M24, explicitement importés en E08).
- Aucun secret en clair : `annuaire/vault-critique.yml` est chiffré (identité « critique ») ; les secrets d'OpenTofu viennent de variables protégées de CI ou de `~/.config/workbook/` sur `adm01`.
- Le compte `admin` de FreeIPA et `kc-secours` de Keycloak sont des comptes de **bris de glace** (RB-240).

## Lancer en local (relecture seulement)

```
admin@adm01:~/src/identite$ uv sync && uv run ansible-galaxy collection install -r collections/requirements.yml -p collections
admin@adm01:~/src/identite$ uv run ansible-playbook annuaire/annuaire.yml --check --diff
```

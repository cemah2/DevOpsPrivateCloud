# Conventions du moteur KV d'OpenBao

> M25-E04 (PLAT-2604). S'applique à tout secret statique rangé dans OpenBao. Une MR qui ajoute un
> chemin hors de ces conventions est refusée.

## Le moteur

| Élément | Valeur |
|---|---|
| Montage | `kv/`, KV **version 2** (versionné) ; aucun autre moteur KV |
| Versions gardées | 10 par secret (`kv/config`, `max_versions`) |
| Écriture conditionnelle (CAS) | non imposée au niveau du moteur ; **imposée par secret** (`cas_required`) dès que deux écrivains peuvent se croiser (personne + pipeline, deux pipelines) |
| Suppression | `bao kv delete` (réversible, `undelete`) pour une erreur ; `bao kv destroy` (irréversible) seulement pour une valeur **compromise**, par l'équipe Plateforme, tracé dans un ticket |

## Arborescence

| Chemin | Contenu | Exemple |
|---|---|---|
| `kv/plateforme/<composant>/<secret>` | secrets des outils de la plateforme | `kv/plateforme/argocd/oidc`, `kv/plateforme/medictl/pve`, `kv/plateforme/openbao/oidc` |
| `kv/<application>/<env>/<secret>` | secrets d'une application, par environnement (`dev`, `recette`, `prod`) | `kv/mediagenda/recette/valkey`, `kv/mediagenda/dev/smtp` |
| `kv/plateforme/essai/…` | essais du workbook, jamais de vraie valeur | `kv/plateforme/essai/demo` |

Un secret regroupe les champs qui **tournent ensemble** (identifiant et mot de passe d'un même compte) ; deux comptes = deux secrets. Les noms de champs sont en minuscules, avec `_` (`client_secret`, `mot_de_passe`, `token_secret`).

Les politiques s'écrivent par préfixe : une équipe reçoit `kv/data/<application>/<env>/*`, jamais `kv/data/*`. Rappel KV v2 : les valeurs sont sous `kv/data/…`, l'historique et les réglages sous `kv/metadata/…`, la suppression douce sous `kv/delete/…` et `kv/undelete/…`, la destruction sous `kv/destroy/…`.

## Métadonnées obligatoires

Posées par `bao kv metadata put -custom-metadata=…` (ou `patch`) à la création du secret. Elles se lisent **sans** la valeur (politiques de lecture, checks, audit).

| Clé | Valeur | Exemple |
|---|---|---|
| `proprietaire` | équipe responsable (groupe Keycloak) | `plateforme`, `mediagenda` |
| `rotation` | fréquence ou déclencheur | `90j`, `annuelle`, `a-chaque-depart`, `jamais` (essai seulement) |
| `source` | qui émet la valeur | `keycloak`, `proxmox`, `genere` |
| `ticket` | ticket de création | `PLAT-2604` |

**Jamais** de valeur secrète dans une métadonnée : elles sont lisibles par les politiques de lecture et par les vérifications.

## Écrire et lire sans laisser de trace

- Écrire : la valeur arrive par l'entrée standard (`champ=-`) ou par un fichier (`champ=@fichier`), jamais en argument (visible dans `ps` et l'historique du shell).
- Lire : `bao kv get -field=<champ>` vers un tube ou un fichier en 600 ; pas d'affichage à l'écran, pas de copie dans un ticket.
- API : le jeton dans un en-tête passé par fichier (`curl -K`), jamais `-H "X-Vault-Token: …"` en clair sur la ligne de commande.

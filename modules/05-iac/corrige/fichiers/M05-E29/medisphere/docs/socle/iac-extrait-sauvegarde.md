<!-- EXTRAIT de docs/socle/iac.md (plateforme/medisphere), section écrite en M05-E29. -->

## Sauvegarde et restauration de l'état

### Trois niveaux

1. **Versionnage** du compartiment `tofu-state` (M05-E11) : chaque écriture d'un état crée une
   version, une suppression crée un marqueur. Restauration : `outils/restaurer-etat.sh --version`.
2. **Sauvegarde de la VM `s3-01`** par PBS (tâche `lab-nuit`, pool `lab`), disque de données
   compris, vers `pbs01` (PAR2).
3. **Copie externe** : job planifié `sauvegarde-etats` (chaque nuit), objets d'état **chiffrés**
   copiés tels quels en artefact de `plateforme/infra`, 90 jours, accès Maintainers ; manifeste
   (`serial`, `lineage`, SHA-256). Restauration : `outils/restaurer-etat.sh --fichier`.

### Scénarios

| Scénario | Couvert par | RPO | RTO |
|---|---|---|---|
| Apply ou commande erronée qui écrit un mauvais état (`state rm`, import faux) | versionnage | 0 (version précédente) | **mesuré : <durée> min** (E29, `envs/lab-m05`) |
| Objet d'état supprimé | versionnage (marqueur de suppression) | 0 | idem |
| État corrompu / illisible | versionnage, sinon copie externe | 0 / 24 h | 15 min / 30 min |
| Perte de `s3-01` (disque, VM) | PBS (restauration de la VM) ou copie externe vers une `s3-01` reconstruite | 24 h | 1 à 2 h (VM) ; **mesuré : <durée> min** pour la restauration de l'état seul (E29, socle sous `_restauration/`) |
| Perte de `pve01` | PBS sur `pbs01` (PAR2), puis copie externe si GitLab est aussi perdu | 24 h | PRA (module F5) |
| **Phrase de chiffrement perdue** | **aucun mécanisme technique** : tous les états, copies comprises, sont illisibles | — | ré-import de toute l'infrastructure (E16) |

La phrase de chiffrement est donc elle-même sauvegardée **hors** du lab (coffre de l'équipe, deux
personnes), et sa relecture depuis le coffre est vérifiée à chaque rotation (registre des secrets).

### Règles

- On ne restaure **jamais** par `tofu state push -force`, ni en éditant un objet.
- Avant toute restauration en place : aucun verrou (RB-050), copie de la version courante (le
  script le fait), et un `tofu plan` juste après — jamais d'apply dans la foulée.
- Un essai de restauration se fait sous `_restauration/<clé>`, dans une copie temporaire de la
  configuration hors de `~/src/infra`, et `_restauration/` est vidé ensuite.
- `tofu state pull` produit un état **en clair** : interdit pour une sauvegarde.

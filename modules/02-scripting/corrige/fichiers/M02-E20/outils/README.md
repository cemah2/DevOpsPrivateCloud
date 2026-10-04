# plateforme/outils

Outils d'exploitation de l'équipe Plateforme MédiSphère :

- `bin/ms-*` : scripts Bash pour les gestes système (collecte de configuration, instantanés, contrôles) ;
- `medictl` : CLI Python qui pilote l'API Proxmox VE (inventaire, cycle de vie des VMs du lab).

## Règles du projet

- Tout changement passe par une merge request vers `main` (branche protégée), relue, avec un pipeline vert.
- Messages de commit au format Conventional Commits (contrôlés par commitlint en local et en CI).
- Les versions (`vX.Y.Z`) sont publiées par semantic-release à partir des messages de commit : on ne pose jamais d'étiquette à la main.
- **Aucun secret dans le dépôt** : les jetons et mots de passe vivent dans `~/.config/workbook/` (fichiers 600) ou dans les variables CI protégées et masquées.
- Un outil d'astreinte échoue bruyamment et clairement : message explicite sur la sortie d'erreur, code retour non nul (0 succès, 1 erreur, 2 usage, 3 refus d'un garde-fou).

Voir [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Démarrer

```
admin@adm01:~$ git clone git@git01.par1.medisphere.internal:plateforme/outils.git ~/src/outils
admin@adm01:~$ cd ~/src/outils
admin@adm01:~/src/outils$ pre-commit install
```

Les tâches du projet (Task 3, `task --list` pour la liste complète ; la CI appelle les mêmes) :

| Commande | Effet |
|---|---|
| `task lint` | ShellCheck et shfmt (réglages de `.shellcheckrc` et `.editorconfig`), ruff |
| `task test` | bats et pytest, rapports JUnit dans `rapports/` (`task test:py -- -k garde` pour filtrer) |
| `task build` | paquet `medictl` dans `dist/`, seulement si les sources ont changé |
| `task install:systeme` | copie figée de `bin/` et `lib/` dans `/usr/local` (sudo) : ce qu'exécutent les services planifiés |
| `task install` | poste de développement : `install:systeme` puis `medictl` depuis la copie de travail (`install:dev`) |
| `task ci` | lint, test, build, dans cet ordre |

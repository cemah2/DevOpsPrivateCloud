# ADR-0321 — Services des équipes en code : environnements par équipe et ApplicationSet

| | |
|---|---|
| Statut | Accepté |
| Date | <AAAA-MM-JJ> |
| Décideurs | Karim Benali, Inès Garnier ; validé par Claire Morel |
| Ticket | DEV-3204 (F2-S04) |
| Complète | ADR-0280 (plateforme développeurs, M28), ADR-0320 (équipe en code) |

## Contexte

Le modèle « Nouveau service » du M28 crée un espace **par service** (`<locataire>-<nom>-dev`) et propose à la Plateforme deux MR (espace, Application). Avec l'équipe en code (ADR-0320), MédiVisio a déjà ses environnements (`medivisio-dev`, `-recette`, `-prod`) avec quotas, coffre, alertes et AppProject. Garder le modèle du M28 aurait créé un espace de plus par service, hors de la description de l'équipe, et deux MR à la Plateforme pour chaque service.

## Décision

1. Une équipe en code déploie **tous ses services dans ses environnements** (`<equipe>-<env>`). Le nom du service n'est plus préfixé (`consultation`) ; le composant du catalogue et l'image le sont (`medivisio-consultation`), pour rester uniques dans l'instance.
2. Les Applications sont produites par l'**ApplicationSet `<equipe>`** (rendu de `plateforme/equipes`) à partir d'un index que l'équipe tient elle-même : `<equipe>/gitops`, un fichier `services/<service>.yaml` par service. Le projet Argo CD, les destinations et la politique de synchronisation sont dans le gabarit (jamais dans une donnée de l'équipe).
3. Le modèle « Nouveau service » v2 crée le code, le dépôt de déploiement (overlays de tous les environnements) et ouvre la MR dans `<equipe>/gitops` ; les équipes historiques gardent le comportement du M28.
4. Ce qui reste à la Plateforme pour un nouveau service : la ligne `services:` du fichier d'équipe (rôles CI d'OpenBao, signature). Mesuré en F2-S04 ; à automatiser (le modèle ouvrira cette MR).

## Conséquences

- Un service de plus = 0 ticket d'infrastructure, une MR courte relue par la Plateforme (rôles CI).
- Les services d'une équipe partagent les quotas de leur environnement : une équipe qui grandit demande un budget plus grand, pas un espace de plus.
- Isolation entre services d'une même équipe : par politiques réseau du dépôt de déploiement, pas par espace (acceptable : même équipe, même responsable).
- Risque : une donnée de l'équipe (`service`) entre dans un nom d'Application et une URL de dépôt ; borné par l'AppProject (dépôts du groupe, espaces de l'équipe) et le schéma du nom (modèle).

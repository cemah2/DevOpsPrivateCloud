# RB-210 — Modèle de runbook d'alerte

> Modèle commun des runbooks d'alerte de MédiSphère (M21-E22, PLAT-2222). Un runbook par alerte
> (ou famille d'alertes), dans `docs/observabilite/metriques/runbooks/`, nommé
> `RB-21x-<sujet>.md`, et pointé par l'annotation `runbook_url` de l'alerte. Une alerte qui pointe
> encore vers ce modèle n'a pas de runbook : c'est une dette, notée à la revue des alertes.

## Règles d'écriture

- **Pour qui** : une personne réveillée à 3 h, qui connaît la plateforme mais pas le détail de
  l'application. Phrases courtes, verbes à l'impératif, une action par ligne.
- **Un écran et demi** au plus. Le détail (architecture, historique) va dans la documentation, avec
  un lien.
- **Chaque commande dit où la lancer** (`admin@adm01:~$`, compte, contexte `kubectl`) et ce qu'on
  attend de sa sortie. Chaque requête PromQL est copiable telle quelle (pas de variable à deviner).
- **Rien de destructif sans avertissement** (`> ⚠️`) et sans retour arrière écrit juste en dessous.
- **Aucun secret**, aucun mot de passe, aucun jeton : on dit où le trouver (Vault, fichier 600).
- Les liens vers les tableaux portent déjà leurs variables (`?var-environnement=prod`).
- Un runbook se **teste** : on le rejoue lors d'un exercice (pannes du palier 4, astreinte) et on
  corrige ce qui a manqué. Date de la dernière vérification en bas de page.

## Sections (dans cet ordre)

1. **Que signifie cette alerte** — la condition en mots simples, le seuil, la durée (`for`).
2. **Impact pour les utilisateurs** — qui est touché, comment ça se voit, à quel point c'est grave.
3. **Premières vérifications (5 minutes)** — dans l'ordre : est-ce réel (vu de l'extérieur, sonde
   du témoin) ? depuis quand ? quelle étendue (un environnement, un pod, tous) ? qu'est-ce qui a
   changé (déploiement, Argo CD, maintenance déclarée) ?
4. **Causes connues et actions** — un tableau « symptôme observé → cause probable → action ».
5. **Escalade** — qui, quand, comment ; seuil d'ouverture d'un incident `INC-48xx`.
6. **Retour à la normale** — comment on sait que c'est fini (requête, tableau), quoi vérifier après.
7. **Après l'incident** — post-mortem si l'impact a dépassé 15 minutes en production ; ce runbook
   est-il à corriger ?

## Ce qu'un runbook ne contient pas

- La théorie (elle est dans la documentation ou l'ADR-0210) ;
- des commandes qui contournent le code (`kubectl edit` en production, modification à la main
  d'un objet géré par Argo CD) — sauf **bris de glace** explicite, avec ticket et retour dans Git ;
- des « il faudrait » : une action est faisable tout de suite, ou c'est une tâche de suivi.

## Gabarit

```markdown
# RB-21x — <Nom de l'alerte> : <phrase courte>

**Alerte** : `<NomAlerte>` (gravité : …, équipe : …) · **Tableau** : <lien> · **Dernière vérification** : AAAA-MM-JJ

## Que signifie cette alerte
## Impact pour les utilisateurs
## Premières vérifications (5 minutes)
## Causes connues et actions
| Ce que tu observes | Cause probable | Action |
|---|---|---|
## Escalade
## Retour à la normale
## Après l'incident
```

*Dernière vérification : à la création (M21-E22).*

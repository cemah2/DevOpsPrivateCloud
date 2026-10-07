# REPRISE.md — Reprendre le travail dans une nouvelle conversation

Ouvre une nouvelle conversation Claude, et colle **un** des messages ci-dessous. C'est tout.

## Produire un bloc

> Dépôt GitHub `cemah2/DevOpsPrivateCloud` (attache-le avec accès en écriture et clone-le). Lis `CLAUDE.md`, `PLAN.md`, `CONVENTIONS.md` et `AVANCEMENT.md`, puis produis le bloc **B** en suivant `CLAUDE.md`, y compris l'enchaînement automatique.

Le bloc A (modules 00 à 06) est produit. Ordre des blocs : A (01-06) → **B (07-11)** → C (12-18) → D+E (19-23) → F (24-26) → G (27-29) → « les finaux F1 à F4 » → « les finaux F5 à F7 ». En temps normal, tu n'as rien à faire : à la fin de chaque bloc, la session planifie elle-même le lancement du suivant (`CLAUDE.md`, « Enchaînement automatique »). Ce message ne sert qu'à relancer la production à la main, en remplaçant « B » par le bloc indiqué dans `AVANCEMENT.md`.

## Reprendre après une interruption

Si une session s'arrête en cours de bloc (limite d'utilisation, coupure), relance **le même message** que ci-dessus, avec le bloc en cours : `AVANCEMENT.md` (statuts des modules et journal) indique où reprendre, et rien de ce qui a été poussé n'est refait.

## Corriger après tes tests

> Dépôt GitHub `cemah2/DevOpsPrivateCloud` (attache-le avec accès en écriture et clone-le). Lis `CLAUDE.md`. Dans le module 00, l'exercice E21 échoue : <colle l'erreur et ce que tu as fait>.

## Règles

- Une conversation à la fois sur le dépôt.
- Ne lance pas un bloc à la main pendant qu'une session planifiée est en cours sur le dépôt.

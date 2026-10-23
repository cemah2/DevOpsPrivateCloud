# État des preuves de conformité

> Généré par `etat-preuves.sh` (F6-S14) — exemple. Compartiment `preuves-conformite`, verrouillage : **oui**.
> Ce fichier est régénéré par le pipeline planifié ; ne pas le modifier à la main.

| Écart | Statut | Preuve (préfixe) | Objets | Dernière preuve | Antérieure à la clôture | Verrou | État |
|---|---|---|---|---|---|---|---|
| ECA-3601 | clos | ECA-3601/ | 4 | 2026-11-12 | oui | oui | OK |
| ECA-3602 | clos | ECA-3602/ | 3 | 2026-11-18 | oui | oui | OK |
| ECA-3603 | clos | ECA-3603/ | 3 | 2026-11-18 | oui | oui | OK |
| ECA-3604 | clos | ECA-3604/ | 2 | 2026-11-09 | oui | oui | OK |
| ECA-3605 | clos | ECA-3605/ | 4 | 2026-11-25 | oui | oui | OK |
| ECA-3606 | clos | ECA-3606/ | 2 | 2026-11-14 | oui | oui | OK |

**Lecture.** « Objets » = nombre de pièces déposées pour l'écart ; « Dernière preuve » = date du dernier
objet ; « Antérieure à la clôture » = la preuve n'a pas été fabriquée après la fermeture de l'écart ;
« Verrou » = inaltérabilité (verrouillage d'objets). Toute ligne non « OK » fait échouer le contrôle et
doit être traitée avant l'audit officiel.

**Collecte.** Les preuves sont collectées par `ms-preuves` (pipeline planifié) ; l'état est régénéré après
chaque collecte. Si une collecte tombe en panne, la preuve vieillit et l'état passe au rouge avant que
l'auditrice ne le constate.

# verif-pbs.sh — mode d'emploi

Vérifie que chaque VM du lab a une sauvegarde de moins de 26 heures sur `pbs01`.

    PBS_PASSWORD=... rebase/verif-pbs.sh [--datastore ds-lab] [--seuil-heures 26]

Le mot de passe (ou le secret du jeton) ne s'écrit jamais dans le script : il vient de
l'environnement, chargé depuis `~/.config/workbook/`.
Code de sortie : 0 ; la liste des VMs en retard s'affiche sur la sortie standard.

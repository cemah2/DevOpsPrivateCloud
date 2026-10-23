<!-- docs/securite/durcissement/runbooks/RB-262-reponse-incident-conteneur.md — EXTRAIT (M26-E42) :
     ce que l'incident INC-5342 ajoute au runbook écrit en E33 (sections 4, 6 et 8). Le reste est inchangé. -->

## 4. Collecte — ajouts après INC-5342

- Conteneur éphémère : `kubectl debug -n <ns> <pod> --image=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37 --target=<conteneur> -- sh -c 'ps -o pid,comm,args; ls -la /tmp'`. Le **nom** d'un processus (`comm`) vient du fichier exécuté : un `kdevtmpfsi` dans `/tmp` se lit dans `ps`, Falco et Tetragon, même s'il ne fait rien.
- Liste des objets de l'espace **avant** toute suppression : `kubectl -n <ns> get deploy,rs,pod,cronjob,job -o yaml > objets.yaml` (la persistance s'y voit).
- Jamais de copie du jeton de compte de service lu par le processus : on note **qu'il** a été lu (événement Falco/Tetragon), pas sa valeur.

## 6. Éradication — ajout

- Ordre : persistance (`CronJob`, `Job`) **puis** charge (`Deployment`) **puis** contrôle qu'aucun pod ne revient pendant deux minutes. Supprimer le Deployment d'abord laisse le CronJob relancer un pod à la minute suivante.

## 8. Retour d'expérience — INC-5342 (exercice M26-E42)

| Étape | Prévu (E33) | Constaté | Action |
|---|---|---|---|
| Détection | alerte Falco en moins de 5 min | <durée relevée> | <règle ajustée, ou rien> |
| Isolement | étiquette + `quarantaine` | <délai, preuve Hubble> | — |
| Collecte | dépôt `preuves/INC-5342/` + empreintes | <nombre de pièces> | — |
| Éradication | Deployment + CronJob | <ordre suivi> | ordre ajouté en section 6 |

Journal de l'incident : `docs/kubernetes/journal/AAAA-MM-JJ-INC-5342.md` ; post-mortem : `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-5342.md`.

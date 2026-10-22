# RB-260 — Répondre à une alerte Falco

> `plateforme/medisphere` — `docs/securite/durcissement/runbooks/RB-260-alerte-falco.md` (M26-E19).
> Alertes : étiquette `source="falco"`, sujet du courriel = nom de la règle. Destinataires : `securite@`
> (toutes), `astreinte@` (gravité critique). Réponse à incident complète : RB-262 (E33).

## Que signifie cette alerte

Falco a vu, dans le noyau d'un nœud, un appel système qui correspond à une règle : un processus a fait
quelque chose qu'une application de MédiSphère ne fait pas. Ce n'est **pas** la preuve d'une attaque ;
c'est un fait daté, sur un pod précis, qu'il faut expliquer.

## Les règles MédiSphère

| Règle | Gravité | Explications légitimes connues |
|---|---|---|
| Shell interactif dans un conteneur applicatif | avertissement | `kubectl exec -it` d'un membre de l'équipe (dev, recette) |
| Lecture du jeton de compte de service | **critique** | Aucune hors instances CNPG (`manager`, déjà exclues) |
| Écriture sous /etc dans un conteneur | **critique** | Aucune (racine en lecture seule) |
| Connexion sortante vers un port non prévu | avertissement | Nouveau flux applicatif non déclaré dans la matrice |
| Binaire exécuté depuis un répertoire temporaire | **critique** | Aucune |
| Exec dans un conteneur de production | avertissement | Intervention tracée par un ticket `CHG-` ou `INC-` |

## Premières vérifications (10 minutes)

1. **Lire l'alerte** : `rule`, `k8s_ns_name`, `k8s_pod_name`, `container_name`, `proc_cmdline`,
   `priority`, l'heure. Ne pas supprimer le pod.
2. **Le contexte dans Loki** (Grafana, organisation Sécurité, source `loki-audit`) :
   ```logql
   {service="falco", k8s_pod_name="<POD>"} | json
   {service="tetragon"} | json | process_exec_process_pod_name="<POD>"
   ```
   Falco dit *ce qui* s'est passé ; Tetragon (E20) donne l'arbre des processus (qui a lancé quoi).
3. **Qui** : pour un `exec`, le journal d'audit de l'API dit quel compte l'a demandé :
   ```logql
   {job="kubernetes-audit"} | json | objectRef_subresource="exec" | objectRef_name="<POD>"
   ```
4. **Le pod existe-t-il encore, a-t-il redémarré ?**
   ```
   admin@adm01:~$ kubectl -n <ESPACE> get pod <POD> -o wide
   admin@adm01:~$ kubectl -n <ESPACE> get events --field-selector involvedObject.name=<POD>
   ```

## Décider

| Constat | Action |
|---|---|
| Action humaine connue, ticket existant (exec en recette, débogage) | Répondre au courriel avec le ticket ; rien d'autre. Si elle se répète, proposer une exception (ci-dessous) |
| Changement légitime non déclaré (nouveau flux, nouvel outil) | L'équipe propriétaire ouvre une MR (matrice des flux, liste Falco) ; exception datée si nécessaire |
| Pas d'explication en 15 minutes, ou gravité critique sans explication | **Incident** : ouvrir un `INC-53xx`, appeler l'astreinte sécurité (Sophie Laurent), appliquer **RB-262** (isolement par l'étiquette `medisphere.internal/quarantaine`, collecte de preuves **avant** toute suppression) |

> ⚠️ **Attention** : supprimer ou redémarrer le pod détruit les preuves (processus, fichiers de `/tmp`,
> connexions). On isole d'abord, on collecte ensuite (RB-262), on reconstruit à la fin.

## Exceptions (faire taire une règle)

On ne modifie ni ne désactive une règle. On ajoute un élément à une **liste** (`medisphere_images_shell_attendu`,
`medisphere_lecteurs_jeton`, `medisphere_ports_sortants`) ou on remplit une **macro**
(`medisphere_exec_prod_attendu`) dans `plateforme/politiques/falco/regles-medisphere.yaml`, par MR, avec
une ligne au registre `docs/securite/durcissement/exceptions.md` (procédure RB-261). Le job `falco:valider`
refuse une règle désactivée ou remplacée.

## Escalade

- Gravité critique sans explication : astreinte (Nadia Roussel organise), sécurité (Sophie Laurent),
  propriétaire de l'application (Julien Petit pour MédiAgenda).
- Falco lui-même muet ou en erreur (aucun événement depuis des heures, pods en échec) : équipe Plateforme
  (Karim Benali) ; c'est une perte de détection, pas un confort.

## Après

Ticket fermé avec : cause, décision (légitime, exception, incident), et si une règle a produit du bruit,
la MR qui le réduit. Le taux de faux positifs par règle se relit chaque mois (requête
`sum by (rule) (count_over_time({service="falco"}[30d]))`).

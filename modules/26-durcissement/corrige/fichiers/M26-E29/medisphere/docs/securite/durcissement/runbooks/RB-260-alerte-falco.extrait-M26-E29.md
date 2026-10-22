<!-- docs/securite/durcissement/runbooks/RB-260-alerte-falco.md — EXTRAIT : section ajoutée en M26-E29. -->

## Politiques d'application de Tetragon : arrêt d'urgence

Politiques concernées : `plateforme/politiques`, dossier `tetragon/application/` (`bloquer-exec-tmp` et
`proteger-fichiers-systeme` dans `wb-essais` ; `proteger-fichiers-systeme` dans `mediagenda-recette`,
pods de l'API). Alerte : `TetragonProcessusTue` (Loki, locataire `audit`).

**Qui** : l'astreinte Plateforme, ou Julien Petit pour `mediagenda-recette` (droits Argo CD sur
l'Application `politiques` : action « désactiver l'auto-synchronisation » seulement, M24).

**Comment** (mesuré le <DATE> en recette : <DURÉE>) :
1. Argo CD, Application `politiques` : désactiver l'auto-synchronisation (sinon `selfHeal` recrée l'objet).
   ```
   admin@adm01:~$ argocd app set politiques --sync-policy none
   ```
2. Supprimer la politique d'application de l'espace touché :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette delete tracingpolicynamespaced proteger-fichiers-systeme
   ```
   Effet immédiat : Tetragon décroche ses programmes eBPF ; aucun pod n'est redémarré.
3. Ouvrir la MR de correction (ou un `git revert`) dans `plateforme/politiques`, puis **réactiver**
   l'auto-synchronisation (`argocd app set politiques --sync-policy automated --self-heal --auto-prune`).
   Une Application laissée sans auto-synchronisation est signalée par le check du mini-projet.

**Avant de conclure au faux positif** : lire l'événement complet (`tetra getevents -o json` sur le nœud,
ou Loki `{service="tetragon"} |= "KPROBE_ACTION"`) : binaire, parent, argument (chemin), conteneur, image.
Un chemin sous `/etc` écrit par l'application elle-même signale une image mal construite (système de
fichiers racine en lecture seule non respecté) : on corrige l'image, pas la politique.

# RB-262 — Réponse à incident : un conteneur compromis

> Déclencheur : alerte Falco/Tetragon ou signalement d'un comportement anormal dans un conteneur
> (processus inattendu, lecture d'un jeton de compte de service, sortie réseau non prévue, binaire
> exécuté depuis `/tmp`, montée de privilèges). Objectif : contenir sans détruire les preuves.

## Principe

**Isoler avant d'éradiquer. Collecter avant de supprimer.** Un conteneur compromis ne s'éteint pas en
premier : on le coupe du réseau (quarantaine), on collecte, puis on éradique (y compris toute
persistance), puis on rétablit.

## 1. Détecter / qualifier (5 min)

- Lire la détection : `loki_requete '{service=~"falco|tetragon"}' audit`, Alertmanager.
- Identifier le pod, le conteneur, le nœud, le processus : `kubectl -n <ns> get pod <pod> -o wide`,
  `kubectl -n <ns> describe pod <pod>`.
- Décider : faux positif (règle à ajuster) ou incident (continuer).

## 2. Isoler (2 min)

- Étiqueter le pod : `kubectl -n <ns> label pod <pod> medisphere.internal/quarantaine=oui`.
- La `CiliumClusterwideNetworkPolicy` `quarantaine` (posée à l'avance) coupe toute entrée/sortie.
- Vérifier : `hubble observe --namespace <ns> --pod <pod> --last 10` (plus de trafic).
- Ne pas supprimer le pod. Ne pas redémarrer le nœud.

## 3. Collecter les preuves (10 min)

- État : `kubectl -n <ns> get pod <pod> -o yaml > pod.yaml`.
- Processus et fichiers : conteneur éphémère `kubectl debug -n <ns> <pod> --image=<busybox> --target=<conteneur> -- sh -c 'ps aux; ls -la /tmp'`.
- Détections : exporter les journaux Falco/Tetragon/audit pertinents.
- (Option) `checkpoint` de conteneur par l'API du kubelet (`ContainerCheckpoint`, statut 1.36 à vérifier),
  ou instantané du disque du nœud (PBS).
- Empreintes `sha256` de chaque preuve ; dépôt dans `s3-01` compartiment `preuves`, chemin `INC-<n>/`.
- **Ne jamais recopier un secret** (jeton, clé) dans les preuves ni le post-mortem.

## 4. Éradiquer (5 min)

- Supprimer la charge : `kubectl -n <ns> delete deployment <nom>`.
- Chercher et supprimer toute **persistance** : `kubectl -n <ns> get cronjob,job` ; un CronJob relance le
  pod chaque minute tant qu'il existe.
- Vérifier qu'aucun pod de l'incident ne subsiste.

## 5. Rétablir et suivre

- Retirer la quarantaine une fois l'espace sain.
- Faire tourner le jeton de compte de service lu, revoir le RBAC et les politiques réseau du pod touché.
- Post-mortem (`docs/kubernetes/post-mortems/`), section Détection : qu'est-ce qui a (ou aurait dû)
  alerter, et en combien de temps.

## À ne jamais faire

- Supprimer le pod avant d'avoir collecté.
- Éradiquer avant d'avoir isolé (la persistance revient).
- Désactiver Falco/Tetragon « le temps de l'incident ».

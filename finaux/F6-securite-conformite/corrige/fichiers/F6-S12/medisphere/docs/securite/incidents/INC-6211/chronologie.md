# INC-6211 — Chronologie et investigation

> `plateforme/medisphere` — `docs/securite/incidents/INC-6211/chronologie.md` (F6-S11/S12).
> Gravité : **G3 mineur** (recette, données fictives, portée limitée). Responsable : astreinte Plateforme.
> RSSI : Sophie Laurent. DPO : Thomas Renaud. Toutes les heures en **UTC**.
> Exemple de référence pour le **vecteur 2** (règles de sortie trop larges) ; les différences du vecteur 1
> (jeton de compte de service fuité) sont indiquées entre crochets.

## Chronologie

| HH:MM | Type | Événement | Source (preuve) |
|---|---|---|---|
| 07:52 | [ouverture] | Alerte Falco « shell interactif » puis « connexion sortante vers un port non prévu », espace `mediagenda-recette` (connexion répétée chaque minute) | Alertmanager, Mailpit (`falco.eml`) |
| 07:55 | [état] | Courriel d'état n° 1 à Sophie, Thomas, Julien ; INC-6211 ouvert | `preuves-conformite/INC-6211/etat-1.eml` |
| 07:58 | [décision] | Qualification : **vrai positif**. Pod `mediagenda-api-7c…-x`, nœud `k8s-w02`, image `…/medisphere/mediagenda-api@sha256:…`, shell ouvert à 07:50:12 | audit API (`audit-exec.json`), Falco (`falco.json`) |
| 08:01 | [action] | Arbre des processus : le `sh` a lancé `cat /var/run/secrets/kubernetes.io/serviceaccount/token` — **en échec**, aucun jeton n'est monté (norme C6, `automountToken: false`), d'où l'absence d'alerte Falco « lecture du jeton » —, puis `base64` et une boucle `python3` détachée | Tetragon `process_exec` (`tetragon.json`), `pod.yaml` (pas de volume de jeton) |
| 08:03 | [action] | Boucle `python3` → `10.10.99.66:4444` toutes les 60 s. Hubble : **FORWARDED** [vecteur 1 : **DROPPED**] | Hubble (`hubble.json`) |
| 08:05 | [action] | Cause du passage : NetworkPolicy `legacy-sortie-large` (MR !218, mars 2026) autorise la sortie vers `10.10.99.0/24`, et la règle `legacy-sortie-recette` posée à chaud sur `gw01` et `gw02` (absente de `/etc/nftables.conf`) la laisse traverser la bordure [vecteur 1 : pas de règle ; un jeton du compte `mediagenda` a été émis à 07:50 (`create serviceaccounts/token`, identité d'administration qui joue l'attaquant dans le lab) puis a servi à `auth can-i --list` + `get pods` (refusé, 403) sous l'identité `system:serviceaccount:mediagenda-recette:mediagenda`, `userAgent` `kubectl/…`, entré par la VIP de l'API] | `netpol.yaml`, `nft-gw01.txt`, `nft-gw02.txt` [audit API] |
| 08:07 | [action] | Journaux du C2 `c2-simule01` relevés : connexions reçues depuis l'IP du pod, **aucun octet utile** [vecteur 1 : C2 muet] | `c2-simule.log` (`c2.log`) |
| 08:10 | [action] | Confinement : étiquette `medisphere.internal/quarantaine=oui` ; `restartCount` inchangé (0) | `pod.yaml` |
| 08:12 | [action] | Pod sorti du ReplicaSet du Rollout `mediagenda` (`app.kubernetes.io/component-`) ; un pod sain recréé ; recette rétablie | `kubectl get pods`, `rollout.yaml` |
| 08:15 | [état] | Escalade RSSI + DPO ; silence Alertmanager ciblé et daté sur le pod isolé | `preuves-conformite/INC-6211/etat-2.eml` |
| 08:40 | [action] | Collecte RB-361 déposée dans `preuves-conformite/INC-6211/` (empreintes ci-dessous) | `SHA256SUMS` |
| 09:30 | [action] | Éradication : `legacy-sortie-large` retirée (MR `plateforme/k8s` !241), règle `legacy-sortie-recette` retirée des deux passerelles par son *handle* ; Hubble confirme le retour en `DROPPED`, compteurs de la bordure figés [vecteur 1 : compte de service supprimé et recréé (tous ses jetons invalidés), baux OpenBao révoqués] | MR !241, `nft-apres.txt` |
| 09:45 | [action] | Rotation des secrets exposés : jeton de compte de service renouvelé, Secrets montés du pod et identifiants OpenBao lisibles depuis le pod tournés | OpenBao (`rotation.txt`) |
| 10:00 | [action] | Pod suspect supprimé **après** collecte et accord RSSI | `kubectl delete pod` |
| 10:10 | [clôture] | Recette saine, aucune alerte Falco active, plus de connexion possible (C2 détruit). Journaux du C2 relevés **avant** `lab/bin/break F6 11 --annuler` | `check F6 12` |

## Portée

- **Établi** : un shell a été ouvert dans un conteneur de l'API de recette ; la lecture du jeton de
  compte de service a été **tentée** et a échoué (aucun jeton monté) ; une connexion vers `10.10.99.66:4444` a été **tentée** ; [vecteur 2 : elle a
  **abouti** (Hubble FORWARDED, C2 journalise) par la politique `legacy-sortie-large` et la règle de bordure `legacy-sortie-recette`] ; [vecteur 1 : elle
  a été **jetée** (Hubble DROPPED, C2 muet) ; un jeton du compte, émis hors du pod, a servi à une reconnaissance en lecture sur l'API].
- **À instruire (vecteur 1)** : l'identité qui a émis le jeton (dans le lab, celle qui a lancé l'injection).
- **Non établi / écarté** : aucune donnée de patient **réelle** touchée — `mediagenda-recette` ne contient
  que des données **fictives/pseudonymisées** (voir `docs/conformite/perimetre.md`) ; **aucun** accès à la
  production (le jeton et les droits sont bornés à l'espace de recette) ; **aucun** octet utile reçu par
  le C2 (le canal, même ouvert en vecteur 2, n'a rien transporté).

## Empreintes des preuves

Déposées dans `preuves-conformite/INC-6211/<horodatage>/`, verrouillage d'objets (F6-S08). Les condensats
`SHA256SUMS` sont recopiés ici à la collecte (RB-361). L'archive d'audit (F6-S08) corrobore la chronologie.

## Cause et suites

Cause (mécanisme) : [vecteur 2] deux règles de sortie temporaires jamais retirées (cluster et bordure),
qu'aucun contrôle ne comparait à l'état déclaré ; [vecteur 1] n'importe quelle identité autorisée à `create serviceaccounts/token` dans l'espace peut fabriquer un jeton du compte de l'application, utilisable hors du cluster, et aucune alerte ne voyait ni l'émission ni l'usage. Suites :
contrôle de dérive des NetworkPolicy, `exec` humain hors bris de glace interdit sur la recette
(`prod-gestes-interactifs` étendu), émission de jetons des comptes applicatifs restreinte et alertée. Décision de notification et
post-mortem : F6-S13.

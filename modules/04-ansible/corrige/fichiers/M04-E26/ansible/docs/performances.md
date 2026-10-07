# Performances d'Ansible — mesures et réglages retenus (M04-E26)

> Exemple de rendu. Les chiffres ci-dessous illustrent l'ordre de grandeur attendu sur le lab de
> référence (adm01 à 2 vCPU, 8 hôtes) ; **les tiens seront différents** : seuls comptent la méthode
> et les écarts relatifs.

## Méthode

- Charge : `playbooks/mesure-perf.yml` (collecte de faits + 10 tâches en lecture, `become`), sur le
  socle (5 hôtes) et la flotte de démonstration (3 hôtes). Chaque exécution donne `changed=0`.
- Outil : `outils/mesurer-perf.sh -n 5`, médiane de 5 exécutions, binaire de l'environnement appelé
  directement (sans `uv run`). Une seule variable changée par rapport à la référence.
- Référence : `ansible.cfg` du projet avant E26 (`forks = 10`, *pipelining* actif, multiplexage
  SSH par défaut d'Ansible, faits complets sans cache, stratégie `linear`).
- Contrôleur : `adm01`, aucune autre exécution en parallèle. Hôtes : mêmes VMs, même charge.

## Résultats (exemple)

| Configuration | n | min (s) | médiane (s) | max (s) |
|---|---|---|---|---|
| Référence (forks 10) | 5 | 21.4 | 22.0 | 23.1 |
| forks 1 | 5 | 96.8 | 98.2 | 99.0 |
| forks 5 | 5 | 30.2 | 31.0 | 31.9 |
| forks 20 | 5 | 21.1 | 21.8 | 22.6 |
| Sans *pipelining* | 5 | 37.9 | 39.5 | 40.2 |
| Sans multiplexage SSH (`ControlMaster=no`, `ControlPath=none`) | 5 | 52.6 | 54.0 | 55.3 |
| Faits : `gather_subset: [min]` | 5 | 17.9 | 18.3 | 19.0 |
| Faits : pas de collecte | 5 | 16.0 | 16.4 | 17.2 |
| Faits : cache `jsonfile` + `smart` (2e exécution) | 5 | 16.2 | 16.6 | 17.4 |
| Stratégie `free` | 5 | 19.0 | 19.9 | 20.8 |

Les trois tâches les plus lentes (`ansible.posix.profile_tasks`) : la collecte de faits (`Gathering
Facts`, ~5 s cumulées), `find` sur `/etc/ssh` (parcours récursif), `slurp` (le contenu revient encodé
en base64).

## Lecture

- **forks** : le temps est ~ (nombre de lots) × (durée d'un lot). Avec 8 hôtes, `forks` ≥ 8 donne un
  seul lot : au-delà, rien ne change. Chaque *fork* est un processus Python d'environ 50 à 80 Mo sur le
  contrôleur : à 500 hôtes, c'est la mémoire et le CPU de `adm01` qui limitent.
- **pipelining** : sans lui, chaque tâche fait plusieurs connexions (création d'un dossier temporaire,
  copie du module, exécution, suppression) ; avec lui, le module passe par l'entrée standard de
  `python3` en une seule commande. Condition : `sudo` sans `requiretty` (cas de Debian). C'est le gain
  le plus important à coût nul.
- **Multiplexage SSH** (`ControlMaster`/`ControlPersist`) : une seule poignée de main SSH par hôte et
  par exécution, les tâches suivantes réutilisent la connexion maître. Sans lui, chaque tâche paie
  l'échange de clés et l'authentification.
- **Faits** : la collecte complète coûte plusieurs secondes par hôte. `gather_subset` (mot-clé de
  play) la réduit ; le cache `jsonfile` + `gathering = smart` l'évite d'une exécution à l'autre.
  Coût : des faits **périmés** (adresse, version du noyau après mise à jour, paquets) pendant
  `fact_caching_timeout`. Un rôle qui décide sur un fait volatil doit appeler
  `ansible.builtin.setup` lui-même, ou on invalide avec `--flush-cache`.
- **Stratégie `free`** : chaque hôte avance à son rythme, sans attendre les autres à chaque tâche.
  Utile quand les hôtes sont indépendants ; à proscrire quand l'ordre compte (gw01 avant les autres,
  `delegate_to`, `run_once`, `serial`) ; sortie plus difficile à lire.
- **async/poll** : pour une tâche longue (mise à jour de paquets) sur beaucoup d'hôtes, lance-la en
  arrière-plan et récupère le résultat plus tard ; sans intérêt pour ces tâches courtes.

## Retenu dans ansible.cfg

| Réglage | Valeur | Justification |
|---|---|---|
| `forks` | 20 | Couvre le parc du bloc A/B en un lot, sans saturer `adm01`. |
| `[connection] pipelining` | True (déjà en E02) | −40 % mesurés, aucun coût sur Debian. |
| Multiplexage SSH | défaut d'Ansible conservé | −60 % mesurés quand on le retire : ne jamais surcharger `ssh_args` sans `ControlPersist`. |
| `gathering`, `fact_caching*` | `smart`, `jsonfile`, `~/.cache/ansible/faits`, 7200 s | −25 % sur une session de travail ; durée courte pour limiter les faits périmés. |
| `callbacks_enabled` | `ansible.posix.timer` | Durée totale toujours visible ; `profile_tasks` à la demande (sortie trop bavarde). |
| Stratégie | `linear` (défaut) | `free` seulement play par play, quand l'ordre n'importe pas. |

## À ne pas activer en CI

- Le **cache de faits** : la CI (et surtout la détection de dérive, E29) doit voir l'état réel ; les
  jobs forcent `ANSIBLE_CACHE_PLUGIN=memory` et `ANSIBLE_GATHERING=implicit`.
- `profile_tasks` : journaux de jobs illisibles. `timer` suffit.
- `ANSIBLE_STRATEGY=free` globalement : l'ordre de `site.yml` (gw01 en premier) compte.

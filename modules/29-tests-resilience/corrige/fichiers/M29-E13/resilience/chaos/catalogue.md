# Catalogue des expériences de chaos — `plateforme/resilience/chaos/`

> Chaque expérience est un fichier versionné, relu en MR, **appliqué depuis `adm01`** dans l'espace `chaos-experiences` (exception écrite à « rien à la main hors Argo CD », ADR-0290). En tête de chaque fichier : hypothèse, mesure, critère d'arrêt, arrêt d'urgence. Arrêt de tout : `outils/chaos-arret.sh` ; procédure : RB-294.
>
> Espaces visables (filtre de Chaos Mesh) : `mediagenda-recette`, `medinotif-recette`, `wb-essais`. Jamais `*-prod`, `messagerie`, ni un espace de plateforme.

## Série M29-E13 (PLAT-3013) — résultats du <DATE>

Charge : scénario k6 de M29-E06 depuis `adm01`, 15 itérations/s. Ligne de base : p95 ≈ 85 ms, 5xx = 0, 2 pods prêts. *(Chiffres d'un lab de référence : remplace-les par les tiens.)*

| Fichier | Type | Cible | Durée | Hypothèse | Résultat | Date |
|---|---|---|---|---|---|---|
| `e13/01-latence-pooler.yaml` | NetworkChaos `delay` 50 ms ± 10 | API → pooler | 5 min | p95 < 250 ms, 5xx < 1 % | **Confirmée** : p95 ≈ 210 ms (création : 3 allers-retours SQL), 5xx = 0 ; budget de latence consommé ×9 pendant 5 min | <DATE> |
| `e13/02-perte-pooler.yaml` | NetworkChaos `loss` 20 % | API → pooler | 3 min | p95 monte, 5xx < 1 % | **Confirmée en partie** : 5xx = 0, mais p99 ≈ 1,4 s (retransmissions TCP de 200 ms et plus, en série) ; SLO de latence franchi | <DATE> |
| `e13/03-partition-valkey.yaml` | NetworkChaos `partition` `both` | API ↔ Valkey | 2 min | « Valkey est un cache : dégradé, pas cassé » | **Réfutée** : en ≈ 15 s, **plus aucun pod prêt** (`/pret` exige Valkey, sonde de disponibilité en échec), la Gateway répond 503 à tout ; expérience mise en pause à 40 s ; retour en ≈ 10 s. Les requêtes déjà dans un pod prêt servaient bien les créneaux en mode dégradé. → action DEV-3013 : `/pret` ne doit pas dépendre du cache | <DATE> |
| `e13/04-stress-api.yaml` | StressChaos CPU 2 × 80 % | 1 pod API | 5 min | l'HPA ajoute un pod en < 2 min, p95 revient | **Confirmée** : étranglement CPU du conteneur (stress-ng compté dans sa limite), HPA de 2 à 3 pods en ≈ 90 s, p95 du pod stressé ≈ 600 ms, p95 global < 250 ms après 2 min 30 | <DATE> |
| `e13/05-kill-medinotif.yaml` | PodChaos `container-kill` | 1 conteneur MédiNotif | 30 s | aucune notification perdue, ≤ 1 doublon | **Confirmée** : 1 message retraité (journal « envoyé » deux fois pour le même `rendez_vous_id`), 0 perdu, conteneur reparti en 4 s | <DATE> |
| `e13/06-schedule-kill-api.yaml` | Schedule `*/15`, `Forbid`, historique 3 | 1 conteneur API | 30 s × 3 | 0 erreur par exécution | **Réfutée de peu** : 2 à 6 réponses 502 à chaque exécution (requêtes en cours dans le conteneur tué : voir la note) ; **en pause** après la 3ᵉ | <DATE> |
| `e13/07-workflow-degradation.yaml` | Workflow (Serial, Parallel, Suspend, StatusCheck) | API, pooler | 11 min | jamais 3 échecs de `/pret` d'affilée | **Confirmée** : `Accomplished`, aucune interruption | <DATE> |

Note sur le `container-kill` : avec containerd, le `chaos-daemon` envoie directement **SIGKILL** à la tâche du conteneur (`task.Kill(ctx, syscall.SIGKILL)` dans `pkg/chaosdaemon/crclients/containerd/client.go`, v2.8.6) : pas de SIGTERM, pas d'arrêt propre, les requêtes en cours sont perdues, et le pod reste dans les points de terminaison du Service jusqu'à l'échec suivant de sa sonde de disponibilité. Un `pod-kill` passe, lui, par la suppression du pod (sortie des points de terminaison, SIGTERM, délai de grâce, sauf `gracePeriod: 0`). C'est donc une panne plus brutale qu'un déploiement : c'est ce qu'on veut tester.

## Écartées (pour la recette, et pourquoi)

| Type | Raison |
|---|---|
| `IOChaos` | En 2.8, le `chaos-daemon` lance `toda` dans l'espace du conteneur et **remplace un point de montage** (`volumePath`) par un système de fichiers FUSE qui retarde, fait échouer ou corrompt (`mistake`) les opérations (plus de *sidecar* injecté par webhook, c'était la 1.x). Sur `mediagenda-db`, c'est le volume de PostgreSQL : un `mistake` corrompt des pages, un `fault` fait planter l'instance en plein checkpoint. Gain pédagogique faible, risque réel sur des données. Possible plus tard sur une base jetable de `wb-essais`. |
| `TimeChaos` | Décale l'horloge vue par un processus : jetons OIDC, certificats et TTL de Valkey deviennent incohérents ; rien à apprendre sur MédiAgenda que la journée de jeu ne montre mieux. |
| `KernelChaos` | Injection de fautes dans le noyau par BPF (`bpfki`) : exige un noyau et des composants que le lab n'a pas (image `chaos-kernel`), et touche le **nœud** entier, donc d'autres espaces. Interdit. |
| `HTTPChaos` | Pose un mandataire transparent (`tproxy`) devant le port du pod : ne voit pas le TLS de bout en bout et interfère avec Cilium (politiques L7, redirection Envoy). À réévaluer avec Cilium hors du chemin. |
| `DNSChaos` | Exige le serveur DNS de Chaos Mesh (`chaos-dns-server`, désactivé dans nos valeurs) et la modification de la configuration de CoreDNS : changement de plateforme partagé avec la prod. |

## Bornes et garde-fous

- Toute expérience a une `duration` (hors Workflow : `deadline` sur chaque modèle).
- Les `Schedule` sont **en pause** quand ils ne sont pas observés ; jamais de `Schedule` dont l'expérience n'a pas de durée.
- Avant chaque expérience : SLO de recette verts depuis 5 min, annonce dans `docs/qualite/journal/`, terminal ouvert avec la commande de pause.

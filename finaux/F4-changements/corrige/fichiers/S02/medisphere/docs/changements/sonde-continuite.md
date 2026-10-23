# La sonde de continuité

| | |
|---|---|
| Ticket | CHG-3402 (changement standard : ajout d'instruments, aucun effet sur les services) |
| Propriétaire | équipe Plateforme (Karim Benali) |
| Runbook | [RB-340](runbooks/RB-340-sonde-continuite.md) |

Elle juge chaque changement du trimestre : « les cabinets n'ont rien vu » devient un nombre.

## 1. Les trois instruments

| Instrument | Où | Ce qu'il voit | Résolution | Ce qu'il ne voit pas |
|---|---|---|---|---|
| **Charge constante** (k6) | TestRun `sonde-continuite` (espace `k6`), script `plateforme/resilience/continuite/sonde-continuite.js` | ce que vit un utilisateur : lecture des créneaux en **prod** (2 req/s), parcours d'écriture en **recette** (1 itération/s) ; codes, délais, connexions refusées | 5 s (envoi vers Prometheus) | rien quand `k8s-par1` est arrêté (S08) ; la prod en écriture |
| **Sondes blackbox** | `mon01` (rôle `supervision_temoin`, groupes `continuite-*`) | MédiAgenda prod (`/pret`), MédiDoc recette (`/readyz`), RabbitMQ (interface), portail (`readiness`) ; plus tard Legacy-RDV (S10), IP flottante OpenStack (S08), RGW (S07) | 30 s | les coupures plus courtes que l'intervalle ; ce qui est derrière une page qui répond |
| **Tableau** | Grafana, UID `f4-changement-en-cours` (dossier Plateforme) | secondes d'erreur de la période affichée, état par sonde, taux d'erreurs, p95/p99, budget d'erreur Pyrra | — | — |

## 2. Exception à la règle « jamais de charge sur la prod » (M29)

La sonde lit la production, à 2 requêtes par seconde au plus, sur la seule route `GET /api/v1/creneaux`, pour un praticien **fictif** (`dr-sonde-<n>`) : aucune donnée de patient n'est lue, rien n'est écrit. Approuvée par Julien Petit (MédiAgenda) et Claire Morel ; relue par Sophie Laurent (pas de donnée de santé). Le script refuse toute autre cible de production. L'écriture se fait en recette, avec des données factices créées puis annulées.

## 3. La mesure d'interruption

Une série 0/1 par Prometheus, évaluée toutes les 15 s :

| Série | Où | Vaut 1 quand |
|---|---|---|
| `continuite:sonde_en_erreur` | témoin `mon01` | cette sonde échoue |
| `continuite:sondes_en_erreur:max` | témoin `mon01` (fédérée vers le cluster) | au moins une sonde de continuité échoue |
| `continuite:en_erreur` | cluster (`PrometheusRule continuite`, `plateforme/observabilite`) | une sonde échoue, OU la charge k6 reçoit des réponses en erreur, OU MédiAgenda prod renvoie des 5xx |

**Secondes d'erreur cumulées** sur une fenêtre de durée *D* (en secondes) finissant à *FIN* :

```promql
avg_over_time(max(continuite:en_erreur)[<D>s:15s]) * <D>          # évaluée à FIN, Thanos Query
avg_over_time(max(continuite:sondes_en_erreur:max)[<D>s:15s]) * <D> # source « temoin » (k8s-par1 arrêté)
```

C'est une mesure **pessimiste** : un échantillon en erreur compte pour tout son pas (15 s), et le taux des 5xx sur 1 min étale une rafale sur une minute. Elle est faite pour comparer des changements entre eux et à un objectif, pas pour un contrat au dixième de seconde. Outil : `plateforme/observabilite/outils/mesurer-interruption.sh DÉBUT FIN [cluster|temoin] [GROUPES]`.

## 4. Objectifs par défaut

| Changement | Objectif (`mesure-objectif-s`) | Raison |
|---|---|---|
| Montées dans le cluster (S04, S05) | 30 s | tout est redondant ; seuls des redémarrages de pods restent |
| Ceph (S07) | 30 s | réplication 3, quorum de 3, RGW derrière une VIP |
| OpenStack (S08), plan de données seulement | 60 s | un seul contrôleur et une seule passerelle réseau : redémarrage d'OVS |
| Bascule de Legacy-RDV (S13) | 900 s (15 min) | coupure annoncée, gel en écriture |

## 5. Ce que la sonde ne prouve pas

Qu'aucune donnée n'a été perdue (cela se prouve par des comptages : rendez-vous, messages) ; qu'un service non sondé va bien ; qu'un utilisateur d'un autre chemin (VPN d'un cabinet, DNS externe) n'a rien vu. Chaque fiche dit ce qu'elle a vérifié en plus.

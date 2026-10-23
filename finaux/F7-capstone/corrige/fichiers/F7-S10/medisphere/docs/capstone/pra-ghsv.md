# Couverture du GHSV par le PRA de PAR2

> F7-S10 (PLAT-3710). Exigences : ENF-06 (RTO 4 h, RPO 15 min), ENF-07, ENF-08 (test annuel en présence du GHSV, rapport sous 15 jours). Repose sur le PRA du F5 (`docs/pra/`, RB-350, RB-351) : mêmes mécanismes, mêmes jetons, même cellule de crise. Ce document dit ce qui est **ajouté** pour le GHSV et ce qui a été **mesuré**.

## 1. Ce qui est répliqué, et comment

| Élément | PAR1 | PAR2 | Mécanisme | Retard attendu |
|---|---|---|---|---|
| Base (`ghsv-prod`) | `mediagenda-db` (2 instances), archive `cnpg-ghsv` sur `s3-01` | `mediagenda-db-par2` (1 instance), réplique continue en topologie distribuée | archivage des WAL (≤ 5 min, `archive_timeout`) + `filer.sync` vers `s3-02` | quelques minutes |
| Code et configuration | `mediagenda/deploiement` (`overlays/clients/ghsv-prod`) | `overlays/clients/ghsv-prod-par2` | miroirs Git de `adm02`, Argo CD de `k8s-par2` | < 5 min (*push mirror*) |
| Images | Harbor | `reg02` | `cosign copy` planifié | ≤ 1 h |
| Identité | Keycloak (`idp01`), courtier `ghsv-idp` | **non répliqué** dans le PRA v1 du F5 (supervision minimale) : à PAR2, les agents ne peuvent pas se connecter ; le DPI non plus (jetons émis par `idp01`) | — | **écart** (§4) |
| Secrets | OpenBao (`kv/ghsv/*`) | `bao-par2` restauré pendant un PRA (F5-S05) | instantanés Raft | ≤ 1 h |
| Nom | `ghsv.medisphere.internal` → `ghsv.apps.par1…` | → `ghsv.apps.par2…` (TTL 60 s) | bascule DNS du RB-350 | 60 s |

Mémoire de PAR2 : en veille, la réplique seule (≈ 0,3 Gio) ; pendant un PRA, + API (2 × 0,2), cache (0,1), mandataires (2 × 2 × 0,05) ≈ 1 Gio de plus sur `k8s-par2-n01` (5 Go). À ajouter au bilan de mémoire de `hp01` (F5-S02).

## 2. Essai de reprise isolé (sans bascule)

Objectif : mesurer RPO et temps de reprise du GHSV **sans** promouvoir la réplique continue ni toucher à PAR1. Depuis `adm02` :

1. Noter l'heure T0 et le dernier témoin écrit à PAR1 (requête en lecture sur `ghsv-prod`, praticien `PRA-TEMOIN`).
2. Créer l'espace d'essai `ghsv-essai-reprise` dans `k8s-par2` et y appliquer (`kubectl apply -k` depuis le miroir, **instrument d'essai** comme les expériences de chaos, ADR-0290) une grappe `essai-reprise` en `bootstrap.recovery` depuis `cnpg-ghsv` de `s3-02` (serveur `mediagenda-db-prod`, sans `recoveryTarget` : le plus loin possible), puis l'API à 1 réplica qui la lit.
3. Attendre la grappe prête, puis l'API prête ; noter T1. Lire le dernier témoin présent dans la base restaurée.
4. Vérifier une opération de lecture du contrat sur l'API d'essai (port-forward ou route `ghsv-essai.apps.par2.medisphere.internal` avec en-tête `X-MediSphere-Site: par2`).
5. Supprimer l'espace d'essai ; vérifier que la réplique continue est toujours en réplication.

| Mesure | Valeur | Commentaire |
|---|---|---|
| RPO mesuré (dernier témoin PAR1 − dernier témoin restauré) | `<MIN>` | objectif 15 min |
| Temps de restauration de la base (T0 → grappe prête) | `<MIN>` | volume de la PoC : `<Gio>` ; extrapolation au volume réel du GHSV : `<CALCUL>` |
| Temps jusqu'à l'API prête (T0 → T1) | `<MIN>` | |
| RTO estimé d'un vrai PRA | `<H>` | = temps de décision + RB-350 (mesuré au F5 : `<H>`) + reprise du GHSV (ci-dessus, en parallèle de MédiAgenda) |

## 3. Le jour d'un vrai PRA

Le GHSV est repris **avec** MédiAgenda, dans l'ordre du RB-350 (même cellule de crise) : promotion de `mediagenda-db-par2` de `ghsv-prod` par jeton, mise à l'échelle de l'overlay `ghsv-prod-par2`, bascule du nom global. Message au GHSV dès la décision (ESC-10 si sécurité, sinon EXP-01 P1). Rendez-vous de la fenêtre perdue : rejoués depuis le DPI (engagements.md §3).

## 4. Écarts et risques

1. **Identité à PAR2** : sans Keycloak à PAR2, ni les agents ni le DPI ne s'authentifient → RTO non tenu pour l'accès authentifié. Le PRA v1 du F5 l'a mis hors périmètre ; le GHSV l'exige. Traitement proposé : instance Keycloak de secours à PAR2 (restaurée depuis PBS, comme `kms01`) dans le RB-350, prévue par l'architecture cible (§4, ADR-0372) et chiffrée en phase 2 ; risque RSQ-17 de `risques.md`.
2. Test annuel en présence du GHSV (ENF-08) : l'essai isolé ne remplace pas l'exercice complet du F5 ; calendrier dans `docs/pra/calendrier-tests.md`.

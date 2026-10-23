# ADR-0373 — PRA du client GHSV et rendez-vous de la fenêtre perdue

| | |
|---|---|
| Statut | **Accepté** (<DATE>) |
| Décideurs | Claire Morel, Nadia Roussel (cellule de crise), Karim Benali, Julien Petit |
| Ticket | PLAT-3704 (F7-S04) |
| Exigences | ENF-06, ENF-07, ENF-08, ENF-03 ; réponse R-11 |
| Complète | ADR-0350 (site de repli PAR2, F5), RB-350 (bascule), RB-351 (retour) |

## Contexte

ENF-06 : RTO 4 h, RPO 15 min sur un second site. ENF-07 : aucun rendez-vous confirmé perdu. R-11 maintient les deux. Le F5 a construit et mesuré un PRA de MédiAgenda vers PAR2 : topologie distribuée CloudNativePG (réplica continu par le stockage objet), applications à 0 réplica, bascule par jetons ou promotion forcée, noms globaux en CNAME, témoin de RPO. La réplication est **asynchrone** : le RPO maximal théorique est le délai d'archivage des WAL (`archive_timeout`, 5 min par défaut dans CloudNativePG) plus la copie vers PAR2.

## Décision

1. **Même mécanisme que le F5**, décliné pour le locataire : réplica continu du `Cluster` du GHSV dans `k8s-par2` ; objets du GHSV copiés vers `s3-02` ; applications du locataire à 0 réplica dans `k8s-par2`, prêtes à monter (images dans `reg02`, configuration par les miroirs d'`adm02`) ; capacité réservée (NF-08).
2. **RPO** : `archive_timeout` ramené à **1 min** pour le `Cluster` du GHSV (RPO technique visé ≤ 5 min, engagement 15 min) ; témoin de RPO dans `ghsv-prod`. Effet à mesurer : nombre d'objets archivés (un segment de 16 Mo par minute, compressé).
3. **ENF-07 par réconciliation** (principe dans `pra-ghsv.md` et `engagements.md` de F7-S10 ; procédure détaillée dans le runbook d'exploitation du service, RB-370, écrit à la notification) : après une bascule, la fenêtre [dernier témoin retrouvé à PAR2 ; début de l'indisponibilité] est réconciliée avec trois sources :
   - le **DPI**, qui a reçu un `201` pour chaque rendez-vous qu'il a créé ou dont il a été notifié : extraction de ses rendez-vous de la fenêtre, comparée à `listerRendezVous` sur PAR2 ;
   - le **journal des confirmations** (messages publiés par MédiAgenda vers MédiNotif, M27-E08) : la file de PAR1 est perdue avec le site, mais les accusés d'envoi du fournisseur de SMS et de courriel (horodatage, identifiant de rendez-vous) ne le sont pas ;
   - les **journaux d'accès** répliqués (horodatage des `POST` en `201`, sans donnée de santé).
   Chaque rendez-vous retrouvé est recréé (par l'agent ou par le DPI) ; un rendez-vous dont on ne connaît que l'existence donne lieu à un appel du patient par le secrétariat. Rapport de réconciliation au GHSV sous 24 h (NF-12).
4. **Ordre de reprise** (RTO 4 h) : DNS de repli et `bao-par2`/`kms01` restaurés (F5) → Keycloak de repli → promotion de la base du GHSV → API et pièces jointes → vérifications (sondes, témoin, parcours d'écriture) → bascule du CNAME public → information du GHSV → réconciliation.
5. **Test** : un exercice par an en présence du GHSV (ENF-08) et un exercice interne ; RTO, RPO, capacité (NF-08) et réconciliation mesurés.

## Options étudiées

| Option | Pour | Contre | Décision |
|---|---|---|---|
| Réplication **synchrone** inter-sites (réplica synchrone à PAR2) | RPO nul : ENF-07 tenue techniquement | chaque écriture attend PAR2 (latence inter-sites ajoutée au p95) ; si PAR2 ou le lien tombe, il faut choisir entre bloquer les écritures (disponibilité perdue à cause du site de **secours**) et dégrader en asynchrone (garantie perdue au moment où on en a besoin) | **écartée** ; révision si la latence mesurée entre sites est < 2 ms et que le GHSV paie une option « RPO nul » |
| Actif/actif sur deux sites | RTO quasi nul | MédiAgenda n'est pas conçu pour des écritures sur deux primaires (index unique praticien/début, conflits) ; complexité sans exigence | **écartée** |
| **Asynchrone (F5) + réconciliation** | prouvé au F5, sans effet sur le p95, ENF-07 tenue en résultat | procédure manuelle, dépend du DPI ; quelques appels de patients possibles | **retenue** |
| Restauration depuis les sauvegardes seulement (pas de réplica continu) | simple, moins cher | RTO de plusieurs heures dès que la base grossit, RPO = dernière sauvegarde + WAL | **écartée** |

## Conséquences

- Procédure de réconciliation (RB-370) à écrire et à répéter ; la sonde de RPO et le rapport de réconciliation entrent dans le rapport de test (ENF-08).
- Dépendance au DPI : H-10 (le DPI rejoue ses écritures en échec) à confirmer à la notification ; sinon, l'extraction du DPI devient l'unique source pour ses rendez-vous.
- Capacité de PAR2 achetée (architecture, §5.3) : c'est le coût principal de cette décision (S05).
- **Preuve de concept du lab** (F7-S10) : réplica continu de la base du GHSV dans `k8s-par2` (topologie distribuée du F5), témoin de RPO propre au GHSV et **essai de reprise isolé** (grappe restaurée à part, sans promotion ni bascule) ; ni Keycloak ni capacité de production à PAR2 (écarts écrits) ; la bascule réelle du locataire se fait au test annuel (ENF-08).

## Révision

Après chaque exercice ; si le RPO mesuré dépasse 5 min ; si le GHSV demande un RPO nul.

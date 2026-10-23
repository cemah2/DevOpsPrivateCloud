# Phase 5 — Recette Day 1 — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Fichiers : [`fichiers/S13/`](fichiers/S13/) (`outils/` = `plateforme/outils`, `medisphere/` = `plateforme/medisphere`) et [`fichiers/S14/`](fichiers/S14/).

**Validé hors du lab** : `ms-verif-equipe` passe `bash -n` et `shellcheck` ; ses tests ([`tests/ms-verif-equipe/lancer.sh`](fichiers/S13/outils/tests/ms-verif-equipe/lancer.sh), faux `kubectl` et `ldapsearch`) passent : usage, source sans identité, équipe conforme sur les sources simulées, membre désactivé resté dans le groupe, locataire absent, équipe externe.

**Points non testés en conditions réelles** : les appels réels à Keycloak, GitLab, OpenBao, Grafana, Alertmanager et Backstage de l'outil (mêmes API et mêmes identités que les checks du workbook, mais pas rejoués contre le lab) ; la lecture du dossier Grafana d'une équipe (UID = nom de l'équipe) par le compte de vérification (S02 : wb-checks voit tous les dossiers) ; la forme exacte des routes générées par l'opérateur à partir des `AlertmanagerConfig` dans `/api/v2/status` (matcher `equipe="<equipe>"`, accompagné du matcher d'espace ajouté par l'opérateur).

---

### F2-S13 — Recette Day 1

**Solution de référence**

1. *L'outil* — [`bin/ms-verif-equipe`](fichiers/S13/outils/bin/ms-verif-equipe), Bash comme les autres outils de `plateforme/outils` (M02), autonome (aucune dépendance à `ms-commun.sh` pour pouvoir tourner dans un job de CI minimal). Dix contrôles, un par promesse de l'offre de service :

   | Contrôle | Équipe interne | Équipe externe (`ext-*`) |
   |---|---|---|
   | `annuaire` | groupe présent, au moins un membre, aucun membre désactivé encore dedans | idem |
   | `keycloak` | groupe importé | idem |
   | `gitlab` | groupe GitLab, au moins un membre | membres externes, aucun groupe hors du leur |
   | `locataire` | Tenant, propriétaire `oidc:<equipe>`, classes de priorité ; chaque espace : quota, LimitRange, Pod Security | espace(s) `medisphere.internal/prestataire=<equipe>` avec quota, LimitRange, Pod Security |
   | `argocd` | AppProject limité à `<equipe>-*`, sans ressource de cluster ni `*` | **aucun** AppProject |
   | `openbao` | politiques du groupe | **aucune** politique |
   | `grafana` | dossier de l'équipe | non exigé |
   | `alertes` | route `equipe="<equipe>"` | non exigée |
   | `catalogue` | entité `Group` | idem |
   | `slo` | au moins un `ServiceLevelObjective` (`pyrra.dev/equipe`) si un service tourne en prod | non exigé |

   Trois statuts (`OK`, `KO`, `NON-VERIFIE`) ; une source sans identité n'est **jamais** `OK` (elle fait échouer la commande, sauf si elle est citée dans `--ignorer`, et reste alors visible : `IGNORE`). Sortie texte et `--json` ; codes 0 / 1 / 2. Identités : fichier `~/.config/ms-outils/verif-equipe.env` (600) ou variables de CI ; dans le lab, celles de `wb-checks` :
   ```
   admin@adm01:~$ install -m 600 /dev/null ~/.config/ms-outils/verif-equipe.env    # puis renseigne IPA_*, KEYCLOAK_*, GITLAB_*, BAO_*, GRAFANA_*, ALERTMANAGER_URL, BACKSTAGE_*, KUBECONFIG
   admin@adm01:~/src/outils$ bin/ms-verif-equipe medivisio
   Conformité de l'équipe medivisio (interne) — 2026-…
     annuaire     OK         groupe medivisio : 2 membre(s) actif(s)
     keycloak     OK         groupe medivisio importé dans le royaume medisphere
     gitlab       OK         groupe medivisio : 2 membre(s) directs
     locataire    OK         3 espace(s) avec quota, limites et Pod Security
     argocd       OK         AppProject medivisio limité à medivisio-*, sans ressource de cluster
     openbao      OK         groupe medivisio → medivisio-equipe
     grafana      OK         dossier « MédiVisio » (uid medivisio)
     alertes      OK         route d'Alertmanager pour equipe=medivisio
     catalogue    OK         Group medivisio au catalogue
     slo          OK         2 SLO pour un service en production (medivisio-prod)
   admin@adm01:~/src/outils$ bin/ms-verif-equipe ext-axiomdev ; echo "code $?"
     annuaire     KO         groupe ext-axiomdev vide          ← attendu après le départ (S12)
   ```
2. *Tests et CI* — [`tests/ms-verif-equipe/`](fichiers/S13/outils/tests/ms-verif-equipe/) et [extrait de `.gitlab-ci.yml`](fichiers/S13/outils/.gitlab-ci.extrait-F2-S13.yml) : job `test:ms-verif-equipe` (shellcheck, `bash -n`, tests sans réseau), job planifié `conformite:equipes` (rapport JSON en artefact, échec visible), et le job mensuel du rapport de refacturation (S08).
3. *Recette* — vérifications du workbook vertes (`lab/bin/check F2 13` relance S02, S04, S05, S07, S08, S11, S12), [`recette-day1.md`](fichiers/S13/medisphere/docs/accueil/recette-day1.md) complété avec les sorties réelles et les délais mesurés, MR approuvée par Claire, puis l'étiquette :
   ```
   admin@adm01:~/medisphere$ git pull && git tag -a day1-v1 -m "Day 1 : accueil des équipes (MédiVisio, Data, AxiomDev) — recette PLAT-3213, ms-verif-equipe vert pour medivisio et data"
   admin@adm01:~/medisphere$ git push origin day1-v1
   ```

**Explications**
- Une offre de service n'est tenue que si on peut la **vérifier** : l'outil traduit chaque promesse en contrôle, et la vérification quotidienne transforme une dérive (droit ajouté à la main, quota retiré, route d'alertes perdue) en échec visible le lendemain.
- Les équipes externes se vérifient surtout par **l'absence** (pas d'AppProject, pas de politique, pas de groupe hérité) : c'est là que se cachent les risques (S11).
- Tester sans services force à séparer collecte et décision ; un faux `kubectl` en tête du `PATH` suffit à jouer les cas qui comptent.

**Alternatives**
- Un outil en Python (bibliothèques `kubernetes`, `python-gitlab`, `hvac`) : plus de structure pour un outil qui grandira ; mais une dépendance de plus dans les images de CI.
- Des tests de conformité « en code » (Rego/conftest sur le rendu de `plateforme/equipes`, M29) : ils vérifient ce qui **devrait** être, pas ce qui **est** ; complémentaires.
- Les *scorecards* de Backstage (plugins communautaires) : visibles par les équipes, mais elles lisent le catalogue, pas l'annuaire ni le coffre.

**Pièges classiques**
- Considérer « je n'ai pas pu lire » comme « rien à signaler » : faux vert.
- Vérifier les équipes avec un compte administrateur : on voit des choses que la vérification ne devrait pas avoir le droit de lire, et l'outil ne marchera pas en CI.
- Une étiquette posée avant que la MR du rapport soit fusionnée : `day1-v1` pointe sur un état sans preuve.
- Oublier qu'après le départ, `ext-axiomdev` **doit** être rouge sur certains contrôles : la recette dit lesquels et pourquoi.

**En production chez MédiSphère**

`ms-verif-equipe` tourne chaque nuit pour toutes les équipes, ses résultats alimentent une métrique (`medisphere_equipe_conforme{equipe, controle}` par le collecteur *textfile* du runner) et une alerte vers la plateforme ; le rapport JSON est joint à la revue d'accès mensuelle de Sophie.

---

### F2-S14 — Retour d'expérience et feuille de route

**Rédaction de référence** : [`retour-experience.md`](fichiers/S14/medisphere/docs/accueil/retour-experience.md) (les valeurs entre chevrons sont celles de **ton** final ; garde la structure).

**Ce qui la rend bonne**
- Elle part de la **promesse** (offre de service) et mesure contre des **cibles** : chaque écart a sa cause principale.
- Les frictions sont reliées à des tickets réels du final (DEV-3206, DEV-3209, SEC-3211…) avec leur cause racine et leur état : un retour d'expérience n'est pas une impression.
- La satisfaction est recueillie par un questionnaire court et identique pour les trois responsables, avec des citations : les équipes sont les clientes de la plateforme.
- La feuille de route dit **comment** elle est priorisée (valeur × fréquence ÷ effort), qui porte chaque action et à quel indicateur on saura qu'elle a réussi ; les décisions qui ne relèvent pas de la plateforme (capacité, chargeback) sont posées à la direction, pas tranchées en douce.

**Pièges classiques**
- Un bilan qui ne parle que de technique (versions, composants) : le comité veut des délais, des équipes servies, des risques.
- Une feuille de route sans priorité ni capacité : une liste de souhaits.
- Inventer une satisfaction unanime : un retour honnête cite au moins une critique et ce qu'on en fait.

**En production chez MédiSphère**

Le retour d'expérience devient un rituel trimestriel (même structure, indicateurs suivis dans le temps) ; la feuille de route est publiée aux équipes avec les dates, et chaque nouvelle arrivée commence par la lecture du dernier retour.

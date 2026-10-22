# Comparatif GitLab CI / Jenkins pour MédiSphère

> M19-E20 (PLAT-2020). Rédigé par l'équipe Plateforme, relu par Karim Benali. Sert l'ADR-0190 (E30).
> **Exemple de corrigé** : les durées ci-dessous sont des valeurs plausibles pour le lab ; remplace-les
> par **tes** mesures (commandes en fin de document) avant de conclure.

## Périmètre comparé

Le même travail sur `mediagenda/api` : lint (ruff), tests (pytest, rapport JUnit), construction de
l'image par le démon `buildkitd` partagé (TLS mutuel, archive OCI non publiée). Côté GitLab : jobs
`qualite:lint`, `qualite:tests`, `image:construction` (composants v2) ; côté Jenkins : job
`mediagenda-api`, `Jenkinsfile` de la branche `essai-jenkins`, agent en pod de l'espace `jenkins`.

## Mesures (3 exécutions chacune, cache chaud)

| Mesure | GitLab CI | Jenkins | Remarque |
|---|---|---|---|
| Durée médiane de bout en bout | 3 min 40 s | 4 min 55 s | Jenkins : un seul pod séquentiel ; GitLab : lint et tests en parallèle (`needs`) |
| Attente avant le premier pas | 8 s | 35 s | Jenkins : création du pod d'agent + connexion WebSocket + clone sur le contrôleur (Jenkinsfile) puis sur l'agent |
| Mémoire au repos | gestionnaire ≈ 60 Mio | contrôleur ≈ 1,2 Gio | Jenkins garde un contrôleur Java à état |
| Lignes à maintenir pour ce projet | 25 (`.gitlab-ci.yml`) | 95 (`Jenkinsfile`) | le pod d'agent est décrit dans chaque `Jenkinsfile` |
| Lignes de plateforme | composants (≈ 600, partagés par tous les projets) | values + JCasC (≈ 230) + Shared Library à écrire (équivalent des composants) | |
| Greffons à suivre | 0 | 9 épinglés (+ dépendances) | cadence des avis de sécurité Jenkins : plusieurs par mois |

## Exploitation et sécurité

| Critère | GitLab CI | Jenkins |
|---|---|---|
| Identité | le job agit au nom de l'auteur du pipeline, jetons éphémères (`CI_JOB_TOKEN`) | comptes locaux en double de GitLab (SSO au M24 seulement), jeton de déploiement longue durée pour lire le dépôt |
| Secrets | variables protégées et masquées, liées aux références protégées | *credentials* globaux : tout job qui connaît l'identifiant peut les utiliser |
| Surface | gestionnaire sans port entrant (il interroge GitLab) | contrôleur exposé (interface, API, WebSocket des agents), greffons exécutés dans le contrôleur |
| État | aucun (configuration dans les dépôts) | `JENKINS_HOME` (PVC) : historique, greffons, *credentials* ; JCasC limite la dérive mais pas tout |
| Montée de version | une mineure par mois avec GitLab, chart du runner | LTS toutes les 12 semaines + greffons ; risque de greffon cassé |
| Traçabilité MR | statut, rapports de tests, couverture dans la MR | à brancher (greffon GitLab, webhooks, jeton `api`) |

## Ce que Jenkins fait mieux

- Logique de pipeline arbitraire (Groovy), paramètres riches, *Shared Libraries* très expressives.
- Indépendance vis-à-vis de la forge (plusieurs forges, dépôts hors GitLab).
- Écosystème de greffons pour des outils propriétaires que l'équipe rachetée utilise.

## Conclusion

GitLab CI est retenu pour MédiSphère : pour un pipeline équivalent, il est plus rapide (parallélisme
natif), quatre fois plus court à écrire par projet, sans état à sauvegarder, sans greffons à suivre,
et il hérite des identités, des protections de branches et des variables protégées de la forge, que
Jenkins oblige à dupliquer. Jenkins n'apporte rien que les composants CI/CD ne couvrent pour nos
projets ; son contrôleur à état et ses greffons ajoutent une surface d'attaque et une charge de
maintenance que l'équipe n'a pas les moyens d'assumer. Pour l'équipe rachetée : migration de ses
`Jenkinsfile` vers les composants, projet par projet (E31, question 14), Jenkins gardé en lecture
seule le temps de la transition. Jenkins est retiré du cluster au mini-projet (ADR-0190).

## Mesurer (commandes)

```
admin@adm01:~$ ( set -a; . ~/.config/workbook/jenkins-checks.env; set +a
    curl -s -K <(printf 'user = "%s:%s"\n' "$JENKINS_USER" "$JENKINS_TOKEN") \
      'https://jenkins.apps.par1.medisphere.internal/job/mediagenda-api/api/json?tree=builds[number,result,duration]{0,3}' ) \
  | jq -r '.builds[] | "\(.number) \(.result) \(.duration / 1000 | floor) s"'
admin@adm01:~$ curl -s -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-checks.token)") \
    "https://git01.par1.medisphere.internal/api/v4/projects/mediagenda%2Fapi/pipelines?ref=main&status=success&per_page=3" \
  | jq -r '.[].id' | while read -r p; do
      curl -s -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-checks.token)") \
        "https://git01.par1.medisphere.internal/api/v4/projects/mediagenda%2Fapi/pipelines/$p/jobs?per_page=100" \
      | jq -r --arg p "$p" '[.[] | select(.name | test("^(qualite:lint|qualite:tests|image:construction)$"))]
          | def t: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
            "\($p) \((map(.finished_at | t) | max) - (map(.started_at | t) | min)) s"'
    done
```

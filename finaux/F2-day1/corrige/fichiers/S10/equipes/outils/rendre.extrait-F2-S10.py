# plateforme/equipes — outils/rendre.py : CHANGEMENTS de F2-S10 (SEC-3210). EXTRAIT : quatre ajouts au
# générateur de S02 ; le reste est inchangé. Tests correspondants : tests/test_rendre.extrait-F2-S10.py
# (rendu de l'espace, refus d'un hébergement pour une équipe interne, refus d'un espace hors du préfixe du
# locataire hôte), à ajouter à tests/test_rendre.py. config/plateforme.yaml : ajouter
# « outils/gitlab-prestataires.d/ » aux chemins possédés de la cible identite.

# 1. normaliser() — après « "kubernetes": k is not None, » :
#        "hebergement": s.get("hebergement"),

# 2. controler() — dans la boucle, avant « if not e["kubernetes"]: » :
LOCATAIRES_HISTORIQUES = {"mediagenda", "medidoc", "medinotif"}


def controler_hebergement(e: dict, equipes: list[dict], erreurs: list[str]) -> None:
    """Un hébergement : prestataire seulement, sans locataire propre, dans un locataire qui existe,
    dans un espace « <locataire>-<nom sans ext-> »."""
    h, n = e.get("hebergement"), e["nom"]
    if not h:
        return
    if e["type"] != "prestataire":
        erreurs.append(f"{n} : « hebergement » est réservé aux prestataires")
    if e["kubernetes"]:
        erreurs.append(f"{n} : un prestataire hébergé n'a pas de bloc kubernetes (pas de locataire propre)")
    hotes = LOCATAIRES_HISTORIQUES | {x["nom"] for x in equipes if x["kubernetes"] and x["etat"] == "active"}
    if h["locataire"] not in hotes:
        erreurs.append(f"{n} : locataire hôte inconnu : {h['locataire']}")
    court = n.removeprefix("ext-")
    if h["espace"] != f"{h['locataire']}-{court}":
        erreurs.append(f"{n} : l'espace doit s'appeler {h['locataire']}-{court} (préfixe du locataire hôte, nom du prestataire)")
    for projet in (h.get("gitlab_projets") or {}):
        if projet.split("/", 1)[0] in {"plateforme", "formation"}:
            erreurs.append(f"{n} : un prestataire n'accède à aucun projet du groupe {projet.split('/', 1)[0]}")
    if not e["expiration"]:
        erreurs.append(f"{n} : un prestataire hébergé a une date d'expiration")


# 3. rendre_k8s_gitops() — dans la boucle sur les équipes, AVANT le « continue » des équipes sans
#    locataire (une équipe retirée n'est plus rendue : son espace est élagué par Argo CD, RB-329) :
#
#        h = e.get("hebergement")
#        if e["etat"] == "active" and h:
#            ecrire(
#                sortie,
#                f"k8s/equipes/{e['nom']}/espaces/{h['espace']}.yaml",
#                env_j2.get_template("k8s/prestataire.yaml.j2").render(
#                    e=e, h=h, lecteur=(h["role"] == "prestataire-lecteur")
#                ),
#            )
#    Le prestataire n'est PAS ajouté aux utilisateurs Capsule : il ne crée aucun espace, son seul droit
#    est le Role rendu.


# 4. rendre_identite() — à la fin : accès directs aux projets GitLab (job gitlab:prestataires de
#    plateforme/identite, outils/gitlab-prestataire.sh).
def rendre_gitlab_prestataires(equipes: list[dict], sortie, ecrire, yaml_texte) -> None:
    lignes = []
    for e in equipes:
        h = e.get("hebergement")
        if e["etat"] != "active" or not h or not h.get("gitlab_projets"):
            continue
        lignes.append(
            {
                "equipe": e["nom"],
                "groupe_propre": e["groupe_gitlab"],
                "expiration": e["expiration"],
                "personnes": [p["identifiant"] for p in e["personnes"] if p.get("etat", "present") == "present"],
                "projets": dict(sorted(h["gitlab_projets"].items())),
            }
        )
    ecrire(sortie, "identite/outils/gitlab-prestataires.d/equipes.yml", yaml_texte({"gitlab_prestataires": lignes}))

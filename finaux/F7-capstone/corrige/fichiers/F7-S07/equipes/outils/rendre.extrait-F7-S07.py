# plateforme/equipes — outils/rendre.py : CHANGEMENTS de F7-S07 (PLAT-3707). EXTRAIT : cinq ajouts au
# générateur de F2 (S02, S07, S10) ; le reste est inchangé. Tests : tests/test_rendre.extrait-F7-S07.py.
# Gabarit ajouté : gabarits/gitops/client.yaml.j2. config/plateforme.yaml : rien à changer (les fichiers
# rendus restent sous les chemins déjà possédés : equipes/, tofu/equipes.auto.tfvars.json).
#
# Garantie demandée par le ticket : le rendu des équipes EXISTANTES est identique, octet pour octet.
# D'où : aucune clé nouvelle dans les fichiers rendus pour une équipe qui n'est pas un client (la clé
# « clients_en_code » du tfvars de plateforme/secrets est présente mais vide s'il n'y a aucun client :
# c'est le seul changement des fichiers rendus, voulu, et relu dans la MR de propagation).

from __future__ import annotations

from datetime import date
from pathlib import Path

# 1. normaliser() — après « "hebergement": s.get("hebergement"), » (F2-S10) :
#        "client": s.get("client"),


# 2. controler() — dans la boucle sur les équipes, AVANT « if not e["kubernetes"]: » :
#        controler_client(e, erreurs)
def controler_client(e: dict, erreurs: list[str]) -> None:
    """Un client : bloc client cohérent, pas de libre-service, environnements recette et prod
    seulement, dates du contrat lisibles et ordonnées, clés nommées par le client."""
    c, n = e.get("client"), e["nom"]
    if e["type"] != "client":
        if c:
            erreurs.append(f"{n} : le bloc « client » est réservé au type client")
        return
    if not c:
        erreurs.append(f"{n} : un client a un bloc « client »")
        return
    if not e["kubernetes"]:
        erreurs.append(f"{n} : un client a un bloc kubernetes (ses environnements)")
        return
    if e["libre_service"]["espaces"]:
        erreurs.append(f"{n} : un client n'a pas de libre-service")
    envs = set(e["environnements"])
    if envs - {"recette", "prod"}:
        erreurs.append(f"{n} : environnements d'un client : recette et prod seulement ({', '.join(sorted(envs))})")
    if "prod" in envs and e["environnements"]["prod"]["synchronisation"] != "manuelle":
        erreurs.append(f"{n} : la production d'un client se synchronise à la main")
    if e["services"]:
        erreurs.append(f"{n} : un client ne livre pas de service (il en reçoit un : client.application)")
    try:
        debut = date.fromisoformat(c["contrat"]["debut"])
        fin = date.fromisoformat(c["contrat"]["fin"])
        if fin <= debut:
            erreurs.append(f"{n} : fin du contrat avant son début")
    except ValueError:
        erreurs.append(f"{n} : dates du contrat illisibles (AAAA-MM-JJ)")
    groupe = c["identite"]["groupe_agents"]
    if groupe == n or groupe in {p["identifiant"] for p in e["personnes"]}:
        # Le groupe « <client> » donne la lecture du locataire (Capsule) : un agent ne doit jamais y être.
        erreurs.append(f"{n} : le groupe des agents doit être distinct du groupe « {n} » du compte")
    if not c["reversibilite"]["compartiment"].startswith(f"{n}-"):
        erreurs.append(f"{n} : le compartiment de réversibilité commence par « {n}- »")


# 3. rendre_secrets() — après la boucle des équipes, AVANT ecrire(...) ; le dictionnaire écrit
#    devient {"equipes_en_code": donnees, "clients_en_code": clients} :
def clients_pour_secrets(equipes: list[dict]) -> dict:
    """Ce que plateforme/secrets (tofu/clients.tf) crée pour chaque client actif : clés transit
    <client>-<nom>, politiques de réversibilité et de déchiffrement, rôle Kubernetes du témoin."""
    clients = {}
    for e in equipes:
        c = e.get("client")
        if e["etat"] != "active" or not c:
            continue
        clients[e["nom"]] = {
            "cles": sorted(c["cles"]),
            "compartiment": c["reversibilite"]["compartiment"],
            "environnements": sorted(e["environnements"]),
        }
    return clients


# 4. rendre_k8s_gitops() — dans la boucle, remplacer le bloc « g = f"gitops/equipes/{e['nom']}" … »
#    par :
def rendre_gitops_equipe(e: dict, env_j2, sortie: Path, ecrire) -> None:
    g = f"gitops/equipes/{e['nom']}"
    ecrire(sortie, f"{g}/projet.yaml", env_j2.get_template("gitops/projet.yaml.j2").render(e=e))
    if e.get("client"):
        # Un client : ses Applications lisent le dépôt de l'application hébergée (identifiants de dépôt
        # déjà fournis par repo-creds-<groupe> du M20) ; ni index de services, ni identifiants propres.
        ecrire(sortie, f"{g}/client.yaml", env_j2.get_template("gitops/client.yaml.j2").render(e=e, c=e["client"]))
        return
    ecrire(sortie, f"{g}/services.yaml", env_j2.get_template("gitops/applicationset.yaml.j2").render(e=e))
    ecrire(sortie, f"{g}/depot.yaml", env_j2.get_template("gitops/depot.yaml.j2").render(e=e))


# 5. rendre_k8s_gitops() — un client n'est PAS ajouté aux utilisateurs Capsule (il ne crée aucun
#    espace) : remplacer « utilisateurs.append(f"oidc:{e['nom']}") » par :
#        if not e.get("client"):
#            utilisateurs.append(f"oidc:{e['nom']}")
#
#    Et gabarits/k8s/espace.yaml.j2 : dans les étiquettes du Namespace, après « environnement » :
#        {%- if e.client %}
#            # Client externe (F7-S07) : lu par le rapport mensuel, la supervision et la couverture PRA.
#            medisphere.internal/client: {{ e.nom }}
#        {%- endif %}
#
#    Et gabarits/gitops/projet.yaml.j2 : la liste sourceRepos devient :
#        sourceRepos:
#        {%- if e.client %}
#          # Client : le dépôt de l'application hébergée, et lui seul (pas le groupe GitLab du compte).
#          - https://git01.par1.medisphere.internal/{{ e.client.application.depot }}.git
#        {%- else %}
#          - https://git01.par1.medisphere.internal/{{ e.groupe_gitlab }}/*
#        {%- endif %}
#    et le rôle « equipe » de l'AppProject, pour un client, n'a QUE get et logs (les personnes du
#    compte ne synchronisent pas la production du client : c'est la promotion de MédiAgenda qui le fait,
#    par MR approuvée de Julien Petit ou Karim Benali) :
#        {%- if not e.client %}
#                - p, proj:{{ e.nom }}:equipe, applications, sync, {{ e.nom }}/*, allow
#        {%- endif %}

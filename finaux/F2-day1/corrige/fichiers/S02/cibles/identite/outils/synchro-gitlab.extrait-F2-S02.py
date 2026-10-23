# plateforme/identite — outils/synchro-gitlab.py : CHANGEMENTS de F2-S02 (PLAT-3202).
# EXTRAIT : deux modifications de l'outil du M24-E11 ; le reste est inchangé.
#
# 1. Les tables se lisent en plusieurs fichiers : outils/synchro-gitlab.yml (écrit à la main) PUIS
#    outils/synchro-gitlab.d/*.yml (equipes.yml est RENDU par plateforme/equipes) ; personnes et groupes
#    de l'annuaire : annuaire/personnes.yml + annuaire/equipes/personnes.yml, idem pour les groupes.
# 2. Une ligne peut viser une PERSONNE (« personne: ines.garnier ») au lieu d'un groupe de l'annuaire :
#    c'est ainsi que le responsable d'une équipe est Maintainer de son groupe et les autres Developer,
#    sans créer de groupe « <equipe>-responsables » dans l'annuaire (la revendication groups resterait
#    lisible, mais un groupe par rôle et par équipe multiplierait les groupes du portail et du coffre).


def lire_plusieurs(fichiers: list[Path], cle: str) -> list[dict]:
    """Concatène la clé « cle » de chaque fichier existant (un fichier absent est ignoré)."""
    resultat: list[dict] = []
    for f in fichiers:
        if f.exists():
            resultat += lire_yaml(f, cle)
    return resultat


# --- dans calculer_cible(), remplacer la boucle « for ligne in table: » par : ---------------------------

    cible: dict[str, dict[str, int]] = {}
    for ligne in table:
        gitlab, niveau = ligne.get("gitlab"), ligne.get("niveau")
        if niveau not in NIVEAUX:
            raise ErreurDonnees(f"table de synchronisation : niveau refusé vers {gitlab} : {niveau}")
        if not gitlab or "/" in str(gitlab):
            raise ErreurDonnees(f"table de synchronisation : groupe GitLab de premier niveau attendu : {gitlab!r}")
        if "personne" in ligne:
            personne = ligne["personne"]
            if personne not in connues:
                raise ErreurDonnees(f"table de synchronisation : personne inconnue : {personne}")
            concernees = {personne} & actives
        else:
            annuaire = ligne.get("annuaire")
            if annuaire not in membres:
                raise ErreurDonnees(f"table de synchronisation : groupe de l'annuaire inconnu : {annuaire}")
            concernees = membres[annuaire] & actives
        groupe_cible = cible.setdefault(str(gitlab), {})
        for personne in concernees:
            groupe_cible[personne] = max(groupe_cible.get(personne, 0), NIVEAUX[niveau])
    return cible


# --- dans main(), remplacer les trois lectures par : ---------------------------------------------------

        r = args.racine
        personnes = lire_plusieurs([r / "annuaire/personnes.yml"], "annuaire_personnes") + \
            lire_plusieurs([r / "annuaire/equipes/personnes.yml"], "annuaire_personnes_equipes")
        groupes = lire_plusieurs([r / "annuaire/groupes.yml"], "annuaire_groupes") + \
            lire_plusieurs([r / "annuaire/equipes/groupes.yml"], "annuaire_groupes_equipes")
        table = lire_plusieurs([r / "outils/synchro-gitlab.yml", *sorted((r / "outils/synchro-gitlab.d").glob("*.yml"))],
                               "synchro_gitlab")
        cible = calculer_cible(personnes, groupes, table)

# Les règles de CI « changes: » de synchro:gitlab et synchro:gitlab:apercu (M24-E11) ajoutent :
#        - annuaire/equipes/*
#        - outils/synchro-gitlab.d/*
# Rappel des bornes (inchangées) : seuls les groupes GitLab cités sont gérés ; root, svc-* (dont
# svc-equipes, Owner des groupes qu'il crée) et les robots ne sont jamais touchés ; le niveau Owner n'est
# ni donné ni retiré. Le groupe GitLab doit EXISTER : il est créé par le job gitlab:equipes de
# plateforme/equipes avant la propagation.

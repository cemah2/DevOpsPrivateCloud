# plateforme/equipes — tests/test_rendre.py : EXTRAIT, tests ajoutés en F2-S10 (SEC-3210), à la suite des
# tests de S02 (mêmes imports et fixture « donnees »). Ils supposent equipes/ext-axiomdev.yaml présent,
# avec une date de fin réelle (pas le gabarit <AAAA-MM-JJ-FIN-CONTRAT>).


def _prestataire(brutes):
    return next(d for d in brutes if d["metadata"]["nom"] == "ext-axiomdev")


def test_prestataire_heberge_rendu(donnees, tmp_path):
    config, brutes = donnees
    equipes = _equipes(brutes)
    rendre.controler(config, equipes)
    rendre.rendre_k8s_gitops(config, equipes, tmp_path)
    rendre.rendre_gitlab_prestataires(equipes, tmp_path, rendre.ecrire, rendre.yaml_texte)
    objets = list(yaml.safe_load_all((tmp_path / "k8s/equipes/ext-axiomdev/espaces/mediagenda-axiomdev.yaml").read_text()))
    ns = next(o for o in objets if o and o["kind"] == "Namespace")
    assert ns["metadata"]["labels"]["capsule.clastix.io/tenant"] == "mediagenda"
    # Espace d'un prestataire : jamais protégé de l'élagage (son départ le supprime, F2-S12).
    assert "Prune=false" not in str(ns["metadata"].get("annotations", {}))
    liaisons = [o for o in objets if o and o["kind"] == "RoleBinding"]
    assert [s["name"] for rb in liaisons for s in rb["subjects"]] == ["oidc:ext-axiomdev"]
    # Pas d'utilisateur Capsule pour un prestataire : il ne crée aucun espace.
    users = yaml.safe_load((tmp_path / "gitops/valeurs/capsule/utilisateurs-equipes.yaml").read_text())
    assert "oidc:ext-axiomdev" not in [u["name"] for u in users["manager"]["options"]["users"]]
    acces = yaml.safe_load((tmp_path / "identite/outils/gitlab-prestataires.d/equipes.yml").read_text())
    assert acces["gitlab_prestataires"][0]["projets"] == {"mediagenda/api": "developer"}


def test_hebergement_refuse_pour_une_equipe_interne(donnees):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    data = next(d for d in b if d["metadata"]["nom"] == "data")
    data["spec"]["hebergement"] = copy.deepcopy(_prestataire(b)["spec"]["hebergement"])
    with pytest.raises(rendre.Invalide, match="réservé aux prestataires"):
        rendre.controler(config, _equipes(b))


def test_espace_hors_prefixe_du_locataire_refuse(donnees):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    _prestataire(b)["spec"]["hebergement"]["espace"] = "medivisio-axiomdev"
    with pytest.raises(rendre.Invalide, match="doit s'appeler mediagenda-axiomdev"):
        rendre.controler(config, _equipes(b))

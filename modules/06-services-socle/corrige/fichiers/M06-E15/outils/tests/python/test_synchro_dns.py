"""Tests de la génération DNS depuis NetBox (M06-E15) : calcul pur, sans réseau."""

from __future__ import annotations

from medictl import synchro_dns as s


def ip(ident, adresse, nom, statut="active"):
    return {"id": ident, "address": adresse, "dns_name": nom, "status": {"value": statut}}


def zone(*rrsets):
    return {"rrsets": list(rrsets)}


def rrset(nom, typ, contenus, compte="", commentaire="", ttl=300):
    commentaires = [{"content": commentaire, "account": compte}] if (compte or commentaire) else []
    return {
        "name": nom,
        "type": typ,
        "ttl": ttl,
        "records": [{"content": c, "disabled": False} for c in contenus],
        "comments": commentaires,
    }


ZONES_VIDES = {
    "par1.medisphere.internal.": zone(),
    "par2.medisphere.internal.": zone(),
    "10.10.in-addr.arpa.": zone(),
    "20.10.in-addr.arpa.": zone(),
}


def test_voulus_a_et_ptr():
    attendus, anomalies = s.voulus([ip(1, "10.10.20.13/24", "nbx01.par1.medisphere.internal")])
    assert anomalies == []
    assert [(r.zone, r.nom, r.type, r.contenus) for r in attendus] == [
        (
            "10.10.in-addr.arpa.",
            "13.20.10.10.in-addr.arpa.",
            "PTR",
            ["nbx01.par1.medisphere.internal."],
        ),
        ("par1.medisphere.internal.", "nbx01.par1.medisphere.internal.", "A", ["10.10.20.13"]),
    ]


def test_ignore_inactives_sans_nom_et_hors_zone():
    attendus, anomalies = s.voulus(
        [
            ip(1, "10.10.20.21/24", "vault01.par1.medisphere.internal", statut="reserved"),
            ip(2, "10.10.20.22/24", ""),
            ip(3, "10.10.20.23/24", "www.exemple.org"),
        ]
    )
    assert attendus == []
    assert len(anomalies) == 1 and "hors des zones" in anomalies[0]


def test_deux_noms_pour_une_ip_un_seul_ptr():
    attendus, anomalies = s.voulus(
        [
            ip(1, "10.10.20.12/24", "git01.par1.medisphere.internal"),
            ip(2, "10.10.20.12/24", "gitlab.par1.medisphere.internal"),
        ]
    )
    assert len([r for r in attendus if r.type == "PTR"]) == 1
    assert "deux noms" in anomalies[0]


def test_creation_puis_rien_au_second_passage():
    attendus, _ = s.voulus([ip(1, "10.10.20.13/24", "nbx01.par1.medisphere.internal")])
    plan = s.planifier(attendus, ZONES_VIDES)
    assert sorted(plan.a_ecrire) == ["10.10.in-addr.arpa.", "par1.medisphere.internal."]
    a = plan.a_ecrire["par1.medisphere.internal."][0]
    assert a["changetype"] == "REPLACE" and a["comments"][0]["account"] == s.COMPTE

    zones = dict(ZONES_VIDES)
    zones["par1.medisphere.internal."] = zone(
        rrset("nbx01.par1.medisphere.internal.", "A", ["10.10.20.13"], compte=s.COMPTE)
    )
    zones["10.10.in-addr.arpa."] = zone(
        rrset(
            "13.20.10.10.in-addr.arpa.", "PTR", ["nbx01.par1.medisphere.internal."], compte=s.COMPTE
        )
    )
    second = s.planifier(attendus, zones)
    assert second.a_ecrire == {} and second.conflits == []


def test_jamais_toucher_un_rrset_d_un_autre_ecrivain():
    attendus, _ = s.voulus([ip(1, "10.10.99.150/24", "sbx01.par1.medisphere.internal")])
    zones = dict(ZONES_VIDES)
    # Créé par Kea DDNS (pas de commentaire), autre adresse : conflit, aucune écriture.
    zones["par1.medisphere.internal."] = zone(
        rrset("sbx01.par1.medisphere.internal.", "A", ["10.10.99.151"])
    )
    plan = s.planifier(attendus, zones)
    assert "par1.medisphere.internal." not in plan.a_ecrire
    assert "sbx01" in plan.conflits[0]


def test_rrset_opentofu_identique_accepte():
    attendus, _ = s.voulus([ip(1, "10.10.99.20/24", "m06-ipam01.par1.medisphere.internal")])
    zones = dict(ZONES_VIDES)
    zones["par1.medisphere.internal."] = zone(
        rrset(
            "m06-ipam01.par1.medisphere.internal.",
            "A",
            ["10.10.99.20"],
            commentaire="gere-par=opentofu",
        )
    )
    plan = s.planifier(attendus, zones)
    assert plan.conflits == []
    assert "par1.medisphere.internal." not in plan.a_ecrire


def test_suppression_de_ce_que_l_outil_possede_seulement():
    zones = dict(ZONES_VIDES)
    zones["par1.medisphere.internal."] = zone(
        rrset("ancien.par1.medisphere.internal.", "A", ["10.10.20.40"], compte=s.COMPTE),
        rrset("manuel.par1.medisphere.internal.", "A", ["10.10.20.41"]),
        rrset("par1.medisphere.internal.", "SOA", ["dns01.par1.medisphere.internal. …"]),
    )
    plan = s.planifier([], zones)
    assert plan.a_ecrire == {
        "par1.medisphere.internal.": [
            {"name": "ancien.par1.medisphere.internal.", "type": "A", "changetype": "DELETE"}
        ]
    }


def test_ttl_different_reecrit():
    attendus, _ = s.voulus([ip(1, "10.10.20.13/24", "nbx01.par1.medisphere.internal")])
    zones = dict(ZONES_VIDES)
    zones["par1.medisphere.internal."] = zone(
        rrset("nbx01.par1.medisphere.internal.", "A", ["10.10.20.13"], compte=s.COMPTE, ttl=3600)
    )
    plan = s.planifier(attendus, zones)
    assert plan.a_ecrire["par1.medisphere.internal."][0]["ttl"] == s.TTL


def test_adoption_explicite_seulement():
    attendus, _ = s.voulus([ip(1, "10.10.20.11/24", "ca01.par1.medisphere.internal")])
    zones = dict(ZONES_VIDES)
    zones["par1.medisphere.internal."] = zone(
        rrset("ca01.par1.medisphere.internal.", "A", ["10.10.20.11"], ttl=3600)
    )
    zones["10.10.in-addr.arpa."] = zone(
        rrset("11.20.10.10.in-addr.arpa.", "PTR", ["ca01.par1.medisphere.internal."], ttl=3600)
    )
    # Sans adoption : même valeur, pas de propriétaire → on n'y touche pas.
    assert s.planifier(attendus, zones).a_ecrire == {}
    # Avec adoption : A et PTR repris (REPLACE avec le commentaire de l'outil).
    plan = s.planifier(attendus, zones, {"ca01.par1.medisphere.internal"})
    assert sorted(plan.a_ecrire) == ["10.10.in-addr.arpa.", "par1.medisphere.internal."]
    assert all(ligne.startswith("[adopter]") for ligne in plan.resume)


def test_jamais_adopter_un_rrset_opentofu():
    attendus, _ = s.voulus([ip(1, "10.10.99.20/24", "m06-ipam01.par1.medisphere.internal")])
    zones = dict(ZONES_VIDES)
    zones["par1.medisphere.internal."] = zone(
        rrset(
            "m06-ipam01.par1.medisphere.internal.",
            "A",
            ["10.10.99.21"],
            commentaire="gere-par=opentofu",
        )
    )
    plan = s.planifier(attendus, zones, {"m06-ipam01.par1.medisphere.internal"})
    assert "par1.medisphere.internal." not in plan.a_ecrire
    assert plan.conflits

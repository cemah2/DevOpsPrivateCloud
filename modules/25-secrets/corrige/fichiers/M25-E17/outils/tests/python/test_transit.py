"""Tests de medictl.transit (M25-E17) : API d'OpenBao simulée par « responses », aucun réseau."""

from __future__ import annotations

import base64
import json

import pytest
import responses

from medictl.erreurs import ConfigError, ErreurApi
from medictl.transit import (
    ClientTransit,
    chiffrer_champs,
    dechiffrer_champs,
    rechiffrer_champs,
    version_du_chiffre,
)

BASE = "https://openbao.exemple.internal:8200/v1/transit"


def client() -> ClientTransit:
    return ClientTransit(
        "https://openbao.exemple.internal:8200", "jeton-de-test", "medictl-donnees"
    )


def _corps(appel) -> dict:
    return json.loads(appel.request.body)


@responses.activate
def test_chiffrer_envoie_du_base64_par_lot_et_le_jeton_en_en_tete():
    responses.post(
        f"{BASE}/encrypt/medictl-donnees",
        json={
            "data": {
                "batch_results": [{"ciphertext": "vault:v1:AAA="}, {"ciphertext": "vault:v1:BBB="}]
            }
        },
    )
    assert client().chiffrer([b"1234", b"06 12"]) == ["vault:v1:AAA=", "vault:v1:BBB="]
    appel = responses.calls[0]
    assert appel.request.headers["X-Vault-Token"] == "jeton-de-test"
    assert _corps(appel) == {"batch_input": [{"plaintext": "MTIzNA=="}, {"plaintext": "MDYgMTI="}]}


@responses.activate
def test_erreur_d_un_element_du_lot_est_remontee():
    responses.post(
        f"{BASE}/decrypt/medictl-donnees",
        json={
            "data": {
                "batch_results": [
                    {"error": "ciphertext or signature version is disallowed by policy (too old)"}
                ]
            }
        },
    )
    with pytest.raises(ErreurApi, match="too old"):
        client().dechiffrer(["vault:v1:AAA="])


@responses.activate
def test_403_donne_un_message_actionnable_sans_jeton():
    responses.post(
        f"{BASE}/rewrap/medictl-donnees", status=403, json={"errors": ["permission denied"]}
    )
    with pytest.raises(ErreurApi) as exc:
        client().rechiffrer(["vault:v1:AAA="])
    assert "refusé" in str(exc.value)
    assert "jeton-de-test" not in str(exc.value)
    assert "jeton-de-test" not in repr(client())


def test_http_en_clair_refuse():
    with pytest.raises(ConfigError):
        ClientTransit("http://openbao.exemple.internal:8200", "x", "medictl-donnees")


def test_version_du_chiffre():
    assert version_du_chiffre("vault:v12:QUJD") == 12
    with pytest.raises(ValueError):
        version_du_chiffre("1234")


class FauxClient:
    """Transit simulé : « chiffre » en préfixant la version ; rewrap = changer de version."""

    def __init__(self, version: int = 1) -> None:
        self.version = version

    def chiffrer(self, clairs):
        return [f"vault:v{self.version}:" + base64.b64encode(c).decode() for c in clairs]

    def dechiffrer(self, chiffres):
        return [base64.b64decode(c.split(":", 2)[2]) for c in chiffres]

    def rechiffrer(self, chiffres):
        return [f"vault:v{self.version}:" + c.split(":", 2)[2] for c in chiffres]


def test_champs_chiffres_rechiffres_dechiffres():
    fiches = [
        {"vm": "gw01", "code_baie": "4821", "astreinte_tel": "06 00 00 00 01"},
        {"vm": "dns01", "code_baie": "7710", "astreinte_tel": None},
    ]
    faux = FauxClient(version=1)
    assert chiffrer_champs(fiches, {"code_baie", "astreinte_tel"}, faux) == 3
    assert fiches[0]["code_baie"].startswith("vault:v1:")
    assert fiches[1]["astreinte_tel"] is None
    # Idempotent : un champ déjà chiffré n'est pas rechiffré par « chiffrer ».
    assert chiffrer_champs(fiches, {"code_baie"}, faux) == 0
    faux.version = 2
    assert rechiffrer_champs(fiches, {"code_baie", "astreinte_tel"}, faux) == 3
    assert {version_du_chiffre(f["code_baie"]) for f in fiches} == {2}
    assert dechiffrer_champs(fiches, {"code_baie", "astreinte_tel"}, faux) == 3
    assert fiches[0] == {"vm": "gw01", "code_baie": "4821", "astreinte_tel": "06 00 00 00 01"}


def test_document_invalide():
    with pytest.raises(ConfigError):
        chiffrer_champs(["pas un objet"], {"code_baie"}, FauxClient())

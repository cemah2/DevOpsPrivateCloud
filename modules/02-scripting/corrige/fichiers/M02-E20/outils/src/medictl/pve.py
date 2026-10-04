"""Client de l'API Proxmox pour medictl (M02-E15, E16, E17, E21).

Une seule classe parle au réseau : ClientPVE. Le reste du code (CLI, garde-fous,
mise en forme) manipule des dictionnaires et se teste sans Proxmox.

- Lectures (GET) : reprises sur erreurs transitoires (reprises.py).
- Écritures (POST, DELETE) : jamais reprises automatiquement (non idempotentes).
- Toute exception technique est traduite en ErreurApi au message actionnable.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from typing import Any

import requests
from proxmoxer import ProxmoxAPI, ResourceException

from medictl.config import PveConfig, charger_config
from medictl.erreurs import ConfigError, ErreurApi, VmIntrouvable
from medictl.reprises import avec_reprises

# Interface de M02-E08, conservée quand la configuration est partie dans config.py (E19) :
# « from medictl.pve import ConfigError, PveConfig, charger_config, connexion » marche toujours.
__all__ = ["ClientPVE", "ConfigError", "PveConfig", "charger_config", "connexion", "traduire"]

log = logging.getLogger(__name__)


def connexion(cfg: PveConfig, timeout: float = 10) -> ProxmoxAPI:
    """Client proxmoxer authentifié par jeton (M02-E08). Aucun appel réseau ici.

    verify_ssl reçoit le chemin de l'autorité (PVE_CACERT, l'ancre de M02-E08) ou True :
    jamais False. proxmoxer le transmet comme ``verify=`` de CHAQUE requête, si bien que
    REQUESTS_CA_BUNDLE / CURL_CA_BUNDLE ne peuvent pas le remplacer (contrairement à un
    ``session.verify``).
    """
    verification = cfg.verification_tls
    return ProxmoxAPI(
        cfg.hote,
        port=cfg.port,
        service="PVE",
        user=cfg.utilisateur,
        token_name=cfg.nom_jeton,
        token_value=cfg.token_secret,
        verify_ssl=str(verification) if verification is not True else True,
        timeout=timeout,
    )


def traduire(exc: Exception, operation: str) -> ErreurApi:
    """Transforme une exception technique en message utile à l'astreinte."""
    if isinstance(exc, requests.exceptions.SSLError):
        return ErreurApi(
            f"{operation} : certificat de Proxmox refusé. Vérifie PVE_CACERT et que "
            "PVE_API_URL utilise un nom ou une adresse présents dans le certificat"
        )
    if isinstance(exc, (requests.exceptions.ConnectionError, requests.exceptions.Timeout)):
        return ErreurApi(f"{operation} : Proxmox injoignable ({type(exc).__name__})")
    if isinstance(exc, ResourceException):
        if exc.status_code == 401:
            return ErreurApi(
                f"{operation} : jeton refusé (401). Secret erroné, jeton supprimé ou expiré"
            )
        if exc.status_code == 403:
            return ErreurApi(f"{operation} : droits insuffisants (403) — {exc.content}")
        details = f" {exc.errors}" if exc.errors else ""
        return ErreurApi(f"{operation} : HTTP {exc.status_code} {exc.content}{details}")
    return ErreurApi(f"{operation} : {exc}")


class ClientPVE:
    def __init__(
        self,
        api: Any,
        *,
        tentatives: int = 4,
        dormir: Callable[[float], None] = time.sleep,
    ) -> None:
        self._api = api
        self._tentatives = tentatives
        self._dormir = dormir

    @classmethod
    def depuis_config(cls, cfg: PveConfig, *, timeout: int = 15) -> ClientPVE:
        return cls(connexion(cfg, timeout=timeout))

    # --- plomberie -------------------------------------------------------------
    def _lire(self, operation: str, appel: Callable[[], Any]) -> Any:
        log.debug("lecture : %s", operation)
        try:
            return avec_reprises(
                appel, nom=operation, tentatives=self._tentatives, dormir=self._dormir
            )
        except Exception as exc:
            raise traduire(exc, operation) from exc

    def _ecrire(self, operation: str, appel: Callable[[], Any]) -> Any:
        log.info("écriture : %s", operation)
        try:
            return appel()
        except Exception as exc:
            raise traduire(exc, operation) from exc

    # --- lectures ----------------------------------------------------------------
    def vms(self) -> list[dict]:
        """VMs QEMU visibles par le jeton (donc celles du pool lab), triées par VMID."""
        ressources = self._lire(
            "GET /cluster/resources", lambda: self._api.cluster.resources.get(type="vm")
        )
        return sorted((r for r in ressources if r.get("type") == "qemu"), key=lambda r: r["vmid"])

    def vm(self, vmid: int) -> dict:
        for ressource in self.vms():
            if ressource["vmid"] == vmid:
                return ressource
        raise VmIntrouvable(f"VM {vmid} introuvable (inexistante, ou hors du pool lab)")

    def config(self, vm: dict) -> dict:
        noeud, vmid = vm["node"], vm["vmid"]
        return self._lire(
            f"GET config de {vmid}", lambda: self._api.nodes(noeud).qemu(vmid).config.get()
        )

    def etat(self, vm: dict) -> dict:
        noeud, vmid = vm["node"], vm["vmid"]
        return self._lire(
            f"GET état de {vmid}",
            lambda: self._api.nodes(noeud).qemu(vmid).status.current.get(),
        )

    def vmid_libre(self, vmid: int) -> bool:
        """/cluster/nextid?vmid=N répond 400 si N est pris, même par une VM hors de
        nos droits : c'est le seul test fiable avec un jeton limité au pool."""
        try:
            self._api.cluster.nextid.get(vmid=vmid)
            return True
        except ResourceException as exc:
            if exc.status_code == 400:
                return False
            raise traduire(exc, "GET /cluster/nextid") from exc
        except requests.exceptions.RequestException as exc:
            raise traduire(exc, "GET /cluster/nextid") from exc

    def adresses_ipv4(self, vm: dict) -> list[str]:
        """Adresses IPv4 vues par l'agent QEMU (hors boucle locale). [] si l'agent
        ne répond pas : l'inventaire ne doit pas échouer pour une VM arrêtée."""
        noeud, vmid = vm["node"], vm["vmid"]
        try:
            reponse = self._api.nodes(noeud).qemu(vmid).agent("network-get-interfaces").get()
        except (ResourceException, requests.exceptions.RequestException) as exc:
            log.info("agent QEMU de %s indisponible : %s", vmid, exc)
            return []
        adresses = []
        for interface in reponse.get("result", []):
            if interface.get("name") == "lo":
                continue
            for adresse in interface.get("ip-addresses", []):
                ip = adresse.get("ip-address", "")
                if adresse.get("ip-address-type") == "ipv4" and not ip.startswith(
                    ("127.", "169.254.")
                ):
                    adresses.append(ip)
        return adresses

    # --- tâches --------------------------------------------------------------------
    def attendre_tache(self, upid: str, *, delai: float = 600, intervalle: float = 2) -> None:
        """Attend une tâche asynchrone (UPID) et vérifie son code de sortie."""
        noeud = upid.split(":")[1]
        echeance = time.monotonic() + delai
        while True:
            etat = self._lire(
                f"GET statut de la tâche {upid}",
                lambda: self._api.nodes(noeud).tasks(upid).status.get(),
            )
            if etat.get("status") == "stopped":
                sortie = etat.get("exitstatus", "inconnu")
                if sortie == "OK":
                    return
                if str(sortie).startswith("WARNINGS"):
                    log.warning("tâche terminée avec avertissements (%s) : %s", sortie, upid)
                    return
                raise ErreurApi(f"tâche en échec ({sortie}) : {upid}")
            if time.monotonic() >= echeance:
                raise ErreurApi(f"tâche toujours en cours après {delai:.0f} s : {upid}")
            self._dormir(intervalle)

    def attendre_agent(self, vm: dict, *, delai: float = 300, intervalle: float = 3) -> None:
        noeud, vmid = vm["node"], vm["vmid"]
        echeance = time.monotonic() + delai
        while True:
            try:
                self._api.nodes(noeud).qemu(vmid).agent.ping.post()
                return
            except (ResourceException, requests.exceptions.RequestException) as exc:
                if time.monotonic() >= echeance:
                    raise traduire(exc, f"agent QEMU de {vmid} muet après {delai:.0f} s") from exc
                self._dormir(intervalle)

    # --- écritures (jamais reprises) --------------------------------------------------
    def cloner(self, source: dict, vmid: int, nom: str, pool: str) -> str:
        return self._ecrire(
            f"POST clone {source['vmid']} → {vmid}",
            lambda: (
                self._api.nodes(source["node"])
                .qemu(source["vmid"])
                .clone.post(newid=vmid, name=nom, pool=pool)
            ),
        )

    def configurer(self, noeud: str, vmid: int, **parametres: Any) -> str | None:
        """POST …/config : renvoie un UPID quand Proxmox a du travail asynchrone, sinon None."""
        return self._ecrire(
            f"POST config de {vmid}",
            lambda: self._api.nodes(noeud).qemu(vmid).config.post(**parametres),
        )

    def demarrer(self, noeud: str, vmid: int) -> str:
        return self._ecrire(
            f"POST démarrage de {vmid}",
            lambda: self._api.nodes(noeud).qemu(vmid).status.start.post(),
        )

    def arreter(self, noeud: str, vmid: int) -> str:
        return self._ecrire(
            f"POST arrêt de {vmid}",
            lambda: self._api.nodes(noeud).qemu(vmid).status.stop.post(),
        )

    def detruire(self, noeud: str, vmid: int) -> str:
        return self._ecrire(
            f"DELETE {vmid}",
            lambda: (
                self._api.nodes(noeud)
                .qemu(vmid)
                .delete(purge=1, **{"destroy-unreferenced-disks": 1})
            ),
        )

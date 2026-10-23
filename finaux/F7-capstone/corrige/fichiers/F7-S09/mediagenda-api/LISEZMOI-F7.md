# F7-S07 et F7-S09 — correctifs de `mediagenda/api` pour les clients hébergés

Correctifs **additifs** : un cabinet de MédiSphère qui n'envoie ni jeton ni nouveaux paramètres voit exactement la même API qu'avant (mêmes routes, mêmes réponses, aucune variable obligatoire en plus). `apps/` du workbook reste inchangé ; ces changements vont dans le dépôt `mediagenda/api`, par MR, sur l'état du dépôt à la fin du F4 (rappel du M27, traces du M23, notifications du M27-E08).

| Fichier | Nature | Scénario |
|---|---|---|
| `src/mediagenda/portees.py` | **nouveau** module (complet) | S09 |
| `src/mediagenda/config.py` | 3 champs ajoutés (extrait ci-dessous) | S07, S09 |
| `src/mediagenda/app.py` | titre, intergiciel, filtres de liste, `PATCH`, bornes de l'identifiant (extrait ci-dessous) | S07, S09 |
| `src/mediagenda/modeles.py` | modèle `Deplacement` (extrait ci-dessous) | S09 |
| `src/mediagenda/depot.py` | `lister` filtré, `deplacer` (extrait ci-dessous) | S09 |
| `tests/conftest.py` | dépôt en mémoire : mêmes méthodes (extrait ci-dessous) | S09 |
| `tests/test_contrat_ghsv.py` | **nouveau** : tests de contrat côté producteur (complet) | S09 |
| `contrats/ghsv/ORIGINE.md` | origine et empreinte du contrat reçu (complet) | S09 |
| `ci/contrat.yml` | jobs `contrat:ghsv` et `contrat:compatibilite` (complet) | S09 |

Aucune migration de schéma : le contrat v1 n'ajoute aucune donnée (le rappel existe depuis V3/V4 du M27, et l'index unique `(praticien, debut)` de V2 sert les filtres et le déplacement).

## `config.py` — trois champs, tous facultatifs

```python
# Dans la dataclass Settings, après delai_arret :
    titre: str = "MédiAgenda"            # MEDIAGENDA_TITRE : marque blanche (F7-S07), titre OpenAPI
    portees: bool = False                # MEDIAGENDA_PORTEES=oui : contrôle des portées (F7-S09)
    groupe_agents: str = "ghsv-agents"   # MEDIAGENDA_GROUPE_AGENTS : groupe qui vaut les deux portées

# Dans depuis_env(), dans l'appel cls(...) :
            titre=env.get("MEDIAGENDA_TITRE", "MédiAgenda"),
            portees=env.get("MEDIAGENDA_PORTEES", "non").lower() in ("oui", "true", "1"),
            groupe_agents=env.get("MEDIAGENDA_GROUPE_AGENTS", "ghsv-agents"),
```

## `modeles.py` — le déplacement du contrat

```python
class Deplacement(BaseModel):
    """Corps de PATCH /api/v1/rendez-vous/{id} (contrat GHSV v1, opération deplacerRendezVous)."""

    debut: AwareDatetime
    duree_minutes: int | None = Field(default=None, ge=5, le=240)
```

## `app.py` — ce qui change

```python
from fastapi import Path as ParametreChemin   # à côté des autres imports de fastapi
from .modeles import Deplacement               # à côté des autres modèles
from .portees import intergiciel_portees

# 1. Titre : marque blanche (S07). Rien ne change si MEDIAGENDA_TITRE est absent.
    app = FastAPI(title=settings.titre, version=settings.version, lifespan=cycle_de_vie)

# 2. Portées (S09) : enregistré AVANT l'intergiciel « mesurer » — Starlette exécute en premier le
#    dernier enregistré : « mesurer » reste à l'extérieur et compte aussi les 401 et 403.
    if settings.portees:
        app.middleware("http")(intergiciel_portees(settings.groupe_agents))

# 3. Liste filtrée (contrat : praticien, du, au, limite). Sans filtre : comportement d'avant.
    @app.get("/api/v1/rendez-vous")
    def lister(
        request: Request,
        limite: int = Query(100, ge=1, le=1000),
        praticien: str | None = Query(None, min_length=1, max_length=100),
        du: AwareDatetime | None = Query(None),
        au: AwareDatetime | None = Query(None),
    ) -> list[RendezVous]:
        if du is not None and au is not None and au <= du:
            raise HTTPException(422, "« au » doit être postérieur à « du »")
        return request.app.state.depot.lister(limite, praticien=praticien, du=du, au=au)

# 4. Identifiant borné (contrat : entier ≥ 1 ; 0 ou négatif → 422 au lieu de 404), dans obtenir,
#    supprimer et deplacer :
        rdv_id: int = ParametreChemin(ge=1)

# 5. Déplacement atomique (contrat : deplacerRendezVous). 404 inconnu, 409 créneau pris (le rendez-vous
#    reste à son heure : une seule instruction UPDATE, refusée par l'index unique).
    @app.patch("/api/v1/rendez-vous/{rdv_id}")
    def deplacer(request: Request, corps: Deplacement, rdv_id: int = ParametreChemin(ge=1)) -> RendezVous:
        ancien = request.app.state.depot.obtenir(rdv_id)
        if ancien is None:
            raise HTTPException(404, "rendez-vous introuvable")
        try:
            nouveau = request.app.state.depot.deplacer(rdv_id, corps.debut, corps.duree_minutes)
        except ConflitCreneau:
            raise HTTPException(409, "créneau déjà pris pour ce praticien") from None
        if nouveau is None:  # supprimé entre-temps
            raise HTTPException(404, "rendez-vous introuvable")
        # Deux jours touchés : l'ancien et le nouveau.
        _invalider(request.app.state.cache, ancien)
        _invalider(request.app.state.cache, nouveau)
        journal.info("rendez-vous déplacé", extra={"rdv_id": rdv_id, "praticien": nouveau.praticien})
        return nouveau
```

`AwareDatetime` vient de `pydantic` (déjà utilisé par `modeles.py`). Le rappel d'un rendez-vous déplacé : MédiNotif lit l'heure au moment d'envoyer (M27-E08) ; si ta version publie un message de rappel à la création avec l'heure, publie aussi au déplacement (décision écrite dans `ecarts-contrat-v1.md`, écart E-06).

## `depot.py` — filtres et déplacement

```python
# Interface Depot :
    def lister(self, limite: int = 100, *, praticien: str | None = None,
               du: datetime | None = None, au: datetime | None = None) -> list[RendezVous]: ...
    def deplacer(self, rdv_id: int, debut: datetime, duree_minutes: int | None) -> RendezVous | None: ...

# DepotPostgres :
    def lister(self, limite=100, *, praticien=None, du=None, au=None):
        # Conditions constantes ; valeurs toujours en paramètres. « IS NULL OR » garde une seule
        # requête préparée ; l'index unique (praticien, debut) sert le cas du DPI (praticien + période).
        with self._pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT {_COLONNES} FROM rendez_vous"  # noqa: S608
                " WHERE (%(p)s::text IS NULL OR praticien = %(p)s)"
                " AND (%(du)s::timestamptz IS NULL OR debut >= %(du)s)"
                " AND (%(au)s::timestamptz IS NULL OR debut < %(au)s)"
                " ORDER BY debut LIMIT %(l)s",
                {"p": praticien, "du": du, "au": au, "l": limite},
            )
            return [_depuis_ligne(ligne) for ligne in cur.fetchall()]

    def deplacer(self, rdv_id, debut, duree_minutes):
        try:
            with self._pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    "UPDATE rendez_vous SET debut = %s, duree_minutes = COALESCE(%s, duree_minutes)"
                    f" WHERE id = %s RETURNING {_COLONNES}",  # noqa: S608
                    (debut, duree_minutes, rdv_id),
                )
                ligne = cur.fetchone()
                return _depuis_ligne(ligne) if ligne else None
        except errors.UniqueViolation as exc:  # index unique de V2 : le créneau est pris
            raise ConflitCreneau from exc
```

## `tests/conftest.py` — le dépôt en mémoire suit l'interface

```python
    def lister(self, limite=100, *, praticien=None, du=None, au=None):
        choisis = [
            r for r in self.rdv.values()
            if (praticien is None or r.praticien == praticien)
            and (du is None or r.debut >= du) and (au is None or r.debut < au)
        ]
        return sorted(choisis, key=lambda r: r.debut)[:limite]

    def deplacer(self, rdv_id, debut, duree_minutes):
        rdv = self.rdv.get(rdv_id)
        if rdv is None:
            return None
        if any(r.id != rdv_id and r.praticien == rdv.praticien and r.debut == debut for r in self.rdv.values()):
            raise ConflitCreneau
        nouveau = rdv.model_copy(update={"debut": debut, "duree_minutes": duree_minutes or rdv.duree_minutes})
        self.rdv[rdv_id] = nouveau
        return nouveau
```

Puis :

```
admin@adm01:~/src/mediagenda-api$ mkdir -p contrats/ghsv && cp ~/DevOpsPrivateCloud/finaux/F7-capstone/ressources/S01/api-rendez-vous-v1.yaml contrats/ghsv/
admin@adm01:~/src/mediagenda-api$ sha256sum contrats/ghsv/api-rendez-vous-v1.yaml   # à reporter dans ORIGINE.md
admin@adm01:~/src/mediagenda-api$ uv add --dev jsonschema pyyaml   # tests de contrat (versions épinglées par uv.lock)
admin@adm01:~/src/mediagenda-api$ uv run pytest -q && uv run pytest -q -m contrat
admin@adm01:~/src/mediagenda-api$ uv run ruff check . && uv run ruff format --check .
```

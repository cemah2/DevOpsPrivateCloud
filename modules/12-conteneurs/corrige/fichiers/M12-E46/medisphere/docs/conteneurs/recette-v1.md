# Procès-verbal de recette — conteneurs MédiSphère v1

| | |
|---|---|
| **Date de la recette** | <AAAA-MM-JJ> |
| **Participants** | Claire Morel, Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit, <MOI> |
| **Étiquette** | `conteneurs-v1` sur `plateforme/medisphere` (commit `<SHA>`) |

## Contrôle global

- Pendant la recette : `lab/bin/check 12 46` → `<N> OK, 0 KO` (sortie jointe en annexe, <HEURE>).
- Après la destruction de l'environnement : `lab/bin/check 12 46` → `<N> OK, 0 KO` (<AAAA-MM-JJ HH:MM>).

## Démonstrations

| Démonstration | Résultat | Mesure |
|---|---|---|
| Julien : une ligne de MédiAgenda, du commit à la recette | <réussie / réserves> | <durée> (pipeline <durée>, `podman auto-update` <durée>) |
| Sophie : évasion depuis un conteneur de la pile | échec de l'évasion | UID vus de l'hôte, capacités (`capsh --print` : vide), montages |
| Nadia : arrêt brutal de la base (`podman kill mediagenda-pg`) | <résultat> | détection en <durée> (sonde), retour en <durée>, MédiAgenda prête en <durée> |

## Réserves et suites

- <réserve, responsable, échéance>
- Signature des images et analyse de vulnérabilités : M13 (Harbor).

## Environnement

- `ctr02`, `ctr03`, `legacy01` détruites par OpenTofu (état `m12-conteneurs`) le <date> ; objets NetBox et DNS retirés.
- `ctr01` : <détruite le … | **conservée** jusqu'à M13-E02 (migration des images vers Harbor), `WB_M12_CTR01_CONSERVE=1>`.

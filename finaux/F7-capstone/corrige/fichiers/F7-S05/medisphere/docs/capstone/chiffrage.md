# Chiffrage et coût complet sur cinq ans — offre GHSV

> PLAT-3705 (F7-S05). Auteur : équipe Plateforme. Relu par Claire Morel.
> **Prix en ordres de grandeur d'octobre 2026, hors taxes, tous « à vérifier ».** Aucun n'est un devis. Chaque prix unitaire porte sa source ; les hypothèses se changent dans [`chiffrage.csv`](chiffrage.csv) (une ligne par poste et par scénario, totaux recalculables).
> Durée : années 1 à 5 du marché (mars 2027 à février 2032). Investissements comptés en trésorerie l'année 1 ; pour le prix, amortissement linéaire sur 5 ans.

## 1. Hypothèses

| ID | Hypothèse | Valeur | Source (relevé d'octobre 2026, à vérifier) |
|---|---|---|---|
| H-C01 | Serveur hyperviseur (1 × 32 cœurs, 256 à 512 Go, 4 × NVMe 7,68 To, 4 × 25 GbE, 5 ans de garantie) | **35 000 €** l'unité ; commutateur 25 GbE 12 000 € ; routeur-pare-feu 5 000 € ; maintenance 8 %/an | estimation interne ; marché de la mémoire en forte hausse en 2026 (hausses trimestrielles de 80 à 90 % début 2026 selon les analystes du marché des semi-conducteurs) : **demander des devis à validité courte** |
| H-C02 | Part des investissements et coûts de PAR2 imputée au GHSV | **50 %** | PAR2 à pleine capacité est rendu nécessaire par le GHSV, mais profite au PRA de tous nos services |
| H-C03 | Baie en centre de données certifié HDS, énergie comprise ; transit Internet avec anti-DDoS ; liaison inter-sites | baie ≈ 4 kW : **2 500 €/mois** ; transit 1 200 €/mois ; option anti-DDoS 500 €/mois ; liaison 1 500 €/mois | grilles publiques d'hébergeurs français (de l'ordre de 2 700 à 5 500 €/mois pour une baie de 3 à 10 kW chez un grand opérateur) ; ordres de grandeur |
| H-C04 | SMS de rappel | 55 % des rendez-vous (R-05), **0,045 € par SMS** | tarifs publics de passerelles SMS professionnelles en France (ordre de 0,04 à 0,07 € par SMS selon le volume) |
| H-C05 | Test d'intrusion par un prestataire PASSI | **12 000 €/an** | ordres de grandeur publiés (6 000 à 15 000 € par test selon le périmètre) |
| H-C06 | Certifications (extension du périmètre HDS et ISO 27001, audits de surveillance) : part du GHSV | 8 000 €/an (plateforme) ; 6 000 € (nuage) ; 3 000 € (infogérance) | estimation interne ; une certification HDS initiale est de l'ordre de 25 000 à 60 000 € |
| H-C07 | Coût annuel de la plateforme mutualisée (équipe hors run du GHSV, outils, supervision, PBS, salles PAR1) et clé de répartition | **600 000 €/an** ; clé GHSV **8 %** (≈ 6 % du calcul, 9 % du stockage : architecture §5.3) ; PAR1 : 2 baies à 3 000 €/mois, 6 serveurs | estimation interne à confirmer par la direction financière (`ms-showback` du F2 pour la clé) |
| H-C08 | Coût interne d'un jour de travail | **450 €** (95 000 € / 210 jours) | dérivé de H-C09 |
| H-C09 | Coût complet employeur d'un ingénieur confirmé en Île-de-France | **95 000 €/an** (salaire brut ≈ 65 000 €, charges ≈ 45 %) ; astreinte ≈ 4 000 €/an par personne | grilles de salaires publiées pour 2026 (ingénieur DevOps confirmé à Paris : ≈ 55 000 à 72 000 € bruts) |
| H-C10 | Nuage public certifié HDS, fournisseur européen, deux régions, même service reconstruit (Kubernetes, stockage objet, VMs Keycloak/OpenBao/observabilité) | **5 000 €/mois** (fourchette 3 000 à 9 000) + sortie de données 3 000 €/an | pages tarifaires publiques des fournisseurs HDS européens ; ordre de grandeur pour ≈ 45 vCPU, 4 To d'objets, deux zones |
| H-C11 | Infogérance HDS (hébergement + exploitation 24/7 de l'infrastructure sur deux sites) | **9 000 €/mois** (fourchette 6 000 à 15 000) + mise en service 25 000 € | ordres de grandeur publiés pour l'infogérance HDS, extrapolés à deux sites et une astreinte 24/7 |
| H-C12 | Souscription Proxmox VE Standard | **550 € par socket et par an** | tarif public de Proxmox (Basic 370 €, Standard 550 €, Premium 1 100 €) |
| — | Effectif d'exploitation | plateforme 1,2 ETP ; nuage 1,0 ETP ; infogérance 0,6 ETP ; maintenance applicative 0,3 ETP partout | S06 (run) |
| — | Volumétrie | 1,91 à 2,41 millions de rendez-vous/an (H-03, 6 %/an) | ENF-01, R-04 |

## 2. Coût complet du scénario retenu : plateforme MédiSphère

| Poste | Catégorie | Total 5 ans |
|---|---|---|
| Hyperviseurs PAR2 (part) | CAPEX | 52 500 |
| Réseau et pare-feu PAR2 (part) | CAPEX | 17 000 |
| Maintenance matériel, baies (dont quote-part PAR1 45 600), transit, anti-DDoS, liaison, DNS, sonde, copie hors site, souscriptions | OPEX | 272 965 |
| Certifications, test d'intrusion | OPEX | 100 000 |
| SMS | OPEX | 266 200 |
| Exploitation (1,2 ETP) et astreinte | OPEX | 620 000 |
| Projet de mise en service, formation | OPEX | 64 000 |
| Développements (173 j) et maintenance applicative (0,3 ETP) | OPEX | 220 350 |
| Réversibilité (essais et export final) | OPEX | 11 250 |
| Quote-part de la plateforme mutualisée (8 %) | OPEX | 240 000 |
| **Total** | | **1 864 265** |

Par année : 530 568 (année 1, investissements et projet compris), puis 327 611 ; 330 615 ; 333 798 ; 341 673.

**Lecture** : le matériel pèse **4 %** du coût complet. Les personnes (exploitation, astreinte, projet, développement, maintenance : ≈ 894 000 €) en pèsent **48 %**, les SMS **14 %**, la quote-part mutualisée **13 %**. On retrouve la conclusion de l'architecture : la charge du GHSV ne coûte presque rien ; ses **exigences** (deux sites, astreinte, sécurité, rappels) coûtent.

**Coût marginal** (ce que MédiSphère dépense en plus si elle gagne le marché) : le coût complet moins les quotes-parts de l'existant (quote-part mutualisée 240 000, baies et matériel de PAR1 45 600) ≈ **1 578 665 €**. C'est lui qui décide du *go/no-go* ; c'est le coût complet qui fixe le prix.

## 3. Comparaisons sur le même périmètre

| Scénario | Total 5 ans | Année 1 | Années 2 à 5 (moy.) | Ce qui reste à notre charge |
|---|---|---|---|---|
| **Plateforme MédiSphère** (PAR1 + PAR2) | **1 864 265** | 530 568 | 333 424 | tout |
| **Nuage public HDS** (fournisseur européen, deux régions) | **1 589 800** | 406 923 | 295 719 | Kubernetes et tout ce qui est dessus, astreinte, sécurité, activités HDS 5 et 6, PRA entre régions, application |
| **Infogérance HDS** (infrastructure opérée par un tiers) | **1 510 800** | 379 923 | 282 719 | application, support N2/N3 applicatif, pilotage du contrat, PRA applicatif |

Ce qui n'est **pas** comparable et qu'on écrit :
- **Nuage public** : capacité de repli « à la demande » (moins chère en veille) mais **non garantie** le jour d'un sinistre régional ; frais de sortie de données ; dépendance juridique au fournisseur (choisir un fournisseur soumis au seul droit européen pour ESC-03) ; compétences nouvelles à acquérir ; notre plateforme existante reste à payer.
- **Infogérance** : moins de personnel chez nous, mais un tiers de plus entre l'incident et sa résolution (EXP-02 : 15 min de prise en compte), PRA de l'infogérant à auditer, réversibilité à double étage (de l'infogérant vers nous, de nous vers le GHSV), perte de la valeur du F5 (PRA prouvé) et du F6 (preuves) ; le GHSV pourrait lui-même contracter directement avec l'infogérant.
- Les deux alternatives laissent **inemployés** les investissements déjà faits (plateforme, PAR2 du F5, outillage de preuves) : leur coût continue de courir.

## 4. Prix proposé au GHSV (bordereau §11.3)

Marge visée ≈ 15 % du coût complet, prix fermes l'année 1 puis révision Syntec.

| Ligne | Calcul | Prix proposé (HT) |
|---|---|---|
| P1 mise en service | (développements 77 850 + projet 54 000 + formation 10 000) × 1,15 | **165 000 €** |
| P2 redevance mensuelle (≤ 2 millions de rendez-vous/an) | (coût complet − coûts de P1 − P3) × 1,15 ÷ 60 | **32 500 €/mois** |
| P3 par tranche de 100 000 rendez-vous au-delà de 2 millions | SMS (100 000 × 55 % × 0,045 ≈ 2 475 €/an) + capacité, marge | **250 €/mois** par tranche |
| P6 jour d'accompagnement | 450 € × 1,6 (coût d'un jour vendu) | **720 €/jour** |
| P7 export final et destruction | 10 jours + procès-verbal, marge | **15 000 €** |

Montant évalué par le GHSV (§13) : 165 000 + 60 × 32 500 + tranches prévues (1, 2, 3 et 5 tranches les années 2 à 5, soit 11 tranches-années × 3 000 €) + 15 000 ≈ **2 163 000 €** sur cinq ans, pour un coût complet de 1 864 265 € : marge ≈ **299 000 €** (≈ 14 % du chiffre d'affaires). **Point mort** : dès l'année 1 en trésorerie (P1 couvre le projet) si la notification tombe fin janvier et que la vague 1 démarre au 1er mars.

## 5. Sensibilité

Une hypothèse à la fois, effet sur le total 5 ans :

| Variable | Variation | Plateforme | Nuage | Infogérance | Ce que ça change |
|---|---|---|---|---|---|
| Effectif et coût des personnes | ± 30 % | ± 268 000 | ± 236 000 | ± 160 000 | la plus forte ; le classement ne change pas, la marge de la plateforme peut disparaître |
| Prix du SMS | 0,045 → 0,07 € | + 148 000 | + 148 000 | + 148 000 | ne change pas le classement, **divise la marge par deux** : clause de révision du prix des SMS indispensable (ou SMS facturés au réel) |
| Clé de répartition de la plateforme mutualisée | 8 % → 4 % | − 144 000 | — | — | la plateforme passe à ≈ 1,72 M€, au niveau du nuage |
| Prix du nuage public | 3 000 à 9 000 €/mois | — | − 120 000 à + 240 000 | — | le nuage passe devant ou derrière la plateforme |
| Prix de l'infogérance | 6 000 à 15 000 €/mois | — | — | − 180 000 à + 360 000 | idem |
| Prix des serveurs (mémoire) | ± 50 % | ± 46 000 | — | — | **négligeable** sur le total ; c'est le **délai** de livraison qui compte (S06) |
| Deuxième client partageant PAR2 | part PAR2 50 % → 25 % | − 126 000 | — | — | la plateforme devient la moins chère à partir du deuxième client |

## 6. Recommandation

Répondre avec la **plateforme MédiSphère**, au prix du §4. Sur le seul coût du GHSV, l'infogérance et le nuage public sont moins chers (la plateforme coûte de 17 à 23 % de plus), mais l'écart est **à l'intérieur des incertitudes** (personnes, clé de répartition, prix des tiers) et il s'inverse dès un deuxième client ou si la clé de répartition baisse. Les arguments décisifs sont ailleurs : l'investissement dans PAR2 sert aussi le PRA de nos propres services ; le PRA, les preuves et les engagements mesurés existent déjà et se démontrent (phase 3) ; aucune dépendance à un tiers sur le chemin d'un incident P1.

Conditions : clause de révision du prix des SMS ; devis de matériel à validité courte avant le 4 décembre ; validation de H-C07 (coût et clé de la plateforme mutualisée) par la direction financière.

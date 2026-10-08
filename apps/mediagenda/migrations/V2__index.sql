-- V2 : index.
-- Un praticien ne peut pas avoir deux rendez-vous qui commencent à la même heure
-- (l'API répond 409). L'index sert aussi au calcul des créneaux d'un jour.
CREATE UNIQUE INDEX rendez_vous_praticien_debut_uidx ON rendez_vous (praticien, debut);

-- Liste globale triée par date et créneaux « tous praticiens ».
CREATE INDEX rendez_vous_debut_idx ON rendez_vous (debut);

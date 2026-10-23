-- V4 (CONTRACT, M27-E06, DEV-2806) : à livrer SEULEMENT quand plus aucune instance de la
-- version de l'API antérieure à la prise en charge du rappel ne tourne, dans AUCUN environnement
-- (job CI « migrations:compatibilite » vert contre la version en production).
-- Cette migration CASSE la version N-1 : sans défaut, une insertion qui ne nomme pas
-- canal_rappel viole NOT NULL. C'est voulu : la base ne choisit plus à la place du patient ;
-- tout écrivain doit poser le canal explicitement (l'API le fait depuis la version N+1).
SET LOCAL lock_timeout = '5s';
-- VALIDATE parcourt la table : on lui laisse plus de temps qu'à un ALTER instantané.
SET LOCAL statement_timeout = '5min';

-- VALIDATE CONSTRAINT ne prend qu'un verrou SHARE UPDATE EXCLUSIVE : lectures ET écritures
-- continuent pendant le parcours. On le fait AVANT l'ALTER qui prend l'ACCESS EXCLUSIVE (un
-- verrou pris dans une transaction est gardé jusqu'à sa fin : l'ordre compte).
ALTER TABLE rendez_vous VALIDATE CONSTRAINT rendez_vous_canal_rappel_ck;
ALTER TABLE rendez_vous VALIDATE CONSTRAINT rendez_vous_contact_rappel_ck;

-- Instantané (catalogue seulement), mais sous ACCESS EXCLUSIVE : en dernier.
ALTER TABLE rendez_vous ALTER COLUMN canal_rappel DROP DEFAULT;

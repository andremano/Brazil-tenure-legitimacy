-- Queries developed by Andre da Silva Mano | a.dasilvamano[at]utwente.nl | 2025

-----------------------------------
-- BLOCK 23 : traditional claims --
-----------------------------------

/* Traditional claims refer to CAR parcels that: (A) do not overlap with SIGEF or SNCI; (B) the ´tipo de imovel´ is ´AST´or ´PCT´ and 
(C) does not overlap any already registered public land 

The query was developed and revised by the athor from the following ChatGPT 5.2 prompt:

I have a table outputs.public_land_merged plm and another called outputs.car_only co that has a an attribute called tipo_imove. 
I want to produce a table outputs.traditional_claims as the result of: The features of co which tipo_imove are either AST or PCT can 
have a maximum of 1% overlap with the polygons of plm. The output table shall have all the attributes of co and none of plm. 
In addition, I want an extra attribute named compliance_level of type integer that shall remain empty. 
Finally, I want to create the primary key constraint on the id attribute and a spatial index on the geom attribute.

*/
begin;
-- Acre

DROP TABLE IF EXISTS outputs.traditional_claims_acre;

CREATE TABLE outputs.traditional_claims_acre AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 1
  LIMIT 1
),
co_fix AS (
  SELECT
    co.*,
    ST_Multi(
      ST_CollectionExtract(
        ST_Buffer(ST_MakeValid(co.geom),0),
        3
      )
    ) AS geom_fix
  FROM outputs.car_only_acre co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL
    AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf
CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL
  AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(
        ST_Area(
          ST_CollectionExtract(
            ST_Intersection(cf.geom_fix, p.plm_geom_fix),
            3
          )
        ),
        0
      ) <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_acre DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_acre RENAME COLUMN geom_fix TO geom;

ALTER TABLE outputs.traditional_claims_acre
  ADD COLUMN IF NOT EXISTS compliance_level integer;

UPDATE outputs.traditional_claims_acre
SET compliance_level = NULL;

ALTER TABLE outputs.traditional_claims_acre
  ADD CONSTRAINT traditional_claims_acre_pkey PRIMARY KEY (id);

CREATE INDEX traditional_claims_acre_geom_gix
  ON outputs.traditional_claims_acre
  USING GIST (geom);

ANALYZE outputs.traditional_claims_acre;


-- Alagoas


DROP TABLE IF EXISTS outputs.traditional_claims_alagoas;

CREATE TABLE outputs.traditional_claims_alagoas AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 2
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_alagoas co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_alagoas DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_alagoas RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_alagoas ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_alagoas SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_alagoas ADD CONSTRAINT traditional_claims_alagoas_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_alagoas_geom_gix ON outputs.traditional_claims_alagoas USING GIST (geom);
ANALYZE outputs.traditional_claims_alagoas;


-- Amapá 


DROP TABLE IF EXISTS outputs.traditional_claims_amapa;

CREATE TABLE outputs.traditional_claims_amapa AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 3
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_amapa co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_amapa DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_amapa RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_amapa ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_amapa SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_amapa ADD CONSTRAINT traditional_claims_amapa_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_amapa_geom_gix ON outputs.traditional_claims_amapa USING GIST (geom);
ANALYZE outputs.traditional_claims_amapa;


-- Amazonas


DROP TABLE IF EXISTS outputs.traditional_claims_amazonas;

CREATE TABLE outputs.traditional_claims_amazonas AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 4
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_amazonas co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_amazonas DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_amazonas RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_amazonas ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_amazonas SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_amazonas ADD CONSTRAINT traditional_claims_amazonas_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_amazonas_geom_gix ON outputs.traditional_claims_amazonas USING GIST (geom);
ANALYZE outputs.traditional_claims_amazonas;


-- Bahia


DROP TABLE IF EXISTS outputs.traditional_claims_bahia;

CREATE TABLE outputs.traditional_claims_bahia AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 5
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_bahia co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_bahia DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_bahia RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_bahia ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_bahia SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_bahia ADD CONSTRAINT traditional_claims_bahia_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_bahia_geom_gix ON outputs.traditional_claims_bahia USING GIST (geom);
ANALYZE outputs.traditional_claims_bahia;


-- Ceará 

DROP TABLE IF EXISTS outputs.traditional_claims_ceara;

CREATE TABLE outputs.traditional_claims_ceara AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 6
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_ceara co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_ceara DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_ceara RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_ceara ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_ceara SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_ceara ADD CONSTRAINT traditional_claims_ceara_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_ceara_geom_gix ON outputs.traditional_claims_ceara USING GIST (geom);
ANALYZE outputs.traditional_claims_ceara;


-- Distrito Federal 


DROP TABLE IF EXISTS outputs.traditional_claims_distrito_federal;

CREATE TABLE outputs.traditional_claims_distrito_federal AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 7
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_distrito_federal co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_distrito_federal DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_distrito_federal RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_distrito_federal ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_distrito_federal SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_distrito_federal ADD CONSTRAINT traditional_claims_distrito_federal_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_distrito_federal_geom_gix ON outputs.traditional_claims_distrito_federal USING GIST (geom);
ANALYZE outputs.traditional_claims_distrito_federal;


-- Espírito Santo


DROP TABLE IF EXISTS outputs.traditional_claims_espirito_santo;

CREATE TABLE outputs.traditional_claims_espirito_santo AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 8
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_espirito_santo co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_espirito_santo DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_espirito_santo RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_espirito_santo ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_espirito_santo SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_espirito_santo ADD CONSTRAINT traditional_claims_espirito_santo_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_espirito_santo_geom_gix ON outputs.traditional_claims_espirito_santo USING GIST (geom);
ANALYZE outputs.traditional_claims_espirito_santo;


-- Goiás


DROP TABLE IF EXISTS outputs.traditional_claims_goias;

CREATE TABLE outputs.traditional_claims_goias AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 9
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_goias co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_goias DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_goias RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_goias ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_goias SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_goias ADD CONSTRAINT traditional_claims_goias_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_goias_geom_gix ON outputs.traditional_claims_goias USING GIST (geom);
ANALYZE outputs.traditional_claims_goias;


-- Maranhão


DROP TABLE IF EXISTS outputs.traditional_claims_maranhao;

CREATE TABLE outputs.traditional_claims_maranhao AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 10
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_maranhao co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_maranhao DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_maranhao RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_maranhao ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_maranhao SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_maranhao ADD CONSTRAINT traditional_claims_maranhao_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_maranhao_geom_gix ON outputs.traditional_claims_maranhao USING GIST (geom);
ANALYZE outputs.traditional_claims_maranhao;


-- Mato Grosso


DROP TABLE IF EXISTS outputs.traditional_claims_mato_grosso;

CREATE TABLE outputs.traditional_claims_mato_grosso AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 11
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_mato_grosso co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_mato_grosso DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_mato_grosso RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_mato_grosso ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_mato_grosso SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_mato_grosso ADD CONSTRAINT traditional_claims_mato_grosso_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_mato_grosso_geom_gix ON outputs.traditional_claims_mato_grosso USING GIST (geom);
ANALYZE outputs.traditional_claims_mato_grosso;


-- Mato Grosso do Sul


DROP TABLE IF EXISTS outputs.traditional_claims_mato_grosso_do_sul;

CREATE TABLE outputs.traditional_claims_mato_grosso_do_sul AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 12
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_mato_grosso_do_sul co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_mato_grosso_do_sul DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_mato_grosso_do_sul RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_mato_grosso_do_sul ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_mato_grosso_do_sul SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_mato_grosso_do_sul ADD CONSTRAINT traditional_claims_mato_grosso_do_sul_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_mato_grosso_do_sul_geom_gix ON outputs.traditional_claims_mato_grosso_do_sul USING GIST (geom);
ANALYZE outputs.traditional_claims_mato_grosso_do_sul;


-- Minas Gerais 


DROP TABLE IF EXISTS outputs.traditional_claims_minas_gerais;

CREATE TABLE outputs.traditional_claims_minas_gerais AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 13
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_minas_gerais co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_minas_gerais DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_minas_gerais RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_minas_gerais ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_minas_gerais SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_minas_gerais ADD CONSTRAINT traditional_claims_minas_gerais_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_minas_gerais_geom_gix ON outputs.traditional_claims_minas_gerais USING GIST (geom);
ANALYZE outputs.traditional_claims_minas_gerais;


-- Pará 


DROP TABLE IF EXISTS outputs.traditional_claims_para;

CREATE TABLE outputs.traditional_claims_para AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 14
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_para co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_para DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_para RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_para ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_para SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_para ADD CONSTRAINT traditional_claims_para_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_para_geom_gix ON outputs.traditional_claims_para USING GIST (geom);
ANALYZE outputs.traditional_claims_para;


-- Paraíba 


DROP TABLE IF EXISTS outputs.traditional_claims_paraiba;

CREATE TABLE outputs.traditional_claims_paraiba AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 15
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_paraiba co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_paraiba DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_paraiba RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_paraiba ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_paraiba SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_paraiba ADD CONSTRAINT traditional_claims_paraiba_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_paraiba_geom_gix ON outputs.traditional_claims_paraiba USING GIST (geom);
ANALYZE outputs.traditional_claims_paraiba;


-- Paraná 


DROP TABLE IF EXISTS outputs.traditional_claims_parana;

CREATE TABLE outputs.traditional_claims_parana AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 16
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_parana co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_parana DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_parana RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_parana ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_parana SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_parana ADD CONSTRAINT traditional_claims_parana_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_parana_geom_gix ON outputs.traditional_claims_parana USING GIST (geom);
ANALYZE outputs.traditional_claims_parana;


-- Pernambuco 


DROP TABLE IF EXISTS outputs.traditional_claims_pernambuco;

CREATE TABLE outputs.traditional_claims_pernambuco AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 17
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_pernambuco co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_pernambuco DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_pernambuco RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_pernambuco ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_pernambuco SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_pernambuco ADD CONSTRAINT traditional_claims_pernambuco_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_pernambuco_geom_gix ON outputs.traditional_claims_pernambuco USING GIST (geom);
ANALYZE outputs.traditional_claims_pernambuco;


-- Piauí 


DROP TABLE IF EXISTS outputs.traditional_claims_piaui;

CREATE TABLE outputs.traditional_claims_piaui AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 18
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_piaui co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_piaui DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_piaui RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_piaui ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_piaui SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_piaui ADD CONSTRAINT traditional_claims_piaui_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_piaui_geom_gix ON outputs.traditional_claims_piaui USING GIST (geom);
ANALYZE outputs.traditional_claims_piaui;


-- Rio de Janeiro 


DROP TABLE IF EXISTS outputs.traditional_claims_rio_de_janeiro;

CREATE TABLE outputs.traditional_claims_rio_de_janeiro AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 19
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_rio_de_janeiro co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_rio_de_janeiro DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_rio_de_janeiro RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_rio_de_janeiro ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_rio_de_janeiro SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_rio_de_janeiro ADD CONSTRAINT traditional_claims_rio_de_janeiro_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_rio_de_janeiro_geom_gix ON outputs.traditional_claims_rio_de_janeiro USING GIST (geom);
ANALYZE outputs.traditional_claims_rio_de_janeiro;


-- Rio Grande do Norte 


DROP TABLE IF EXISTS outputs.traditional_claims_rio_grande_do_norte;

CREATE TABLE outputs.traditional_claims_rio_grande_do_norte AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 20
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_rio_grande_do_norte co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_rio_grande_do_norte DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_rio_grande_do_norte RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_rio_grande_do_norte ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_rio_grande_do_norte SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_rio_grande_do_norte ADD CONSTRAINT traditional_claims_rio_grande_do_norte_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_rio_grande_do_norte_geom_gix ON outputs.traditional_claims_rio_grande_do_norte USING GIST (geom);
ANALYZE outputs.traditional_claims_rio_grande_do_norte;


-- Rio Grande do Sul 


DROP TABLE IF EXISTS outputs.traditional_claims_rio_grande_do_sul;

CREATE TABLE outputs.traditional_claims_rio_grande_do_sul AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 21
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_rio_grande_do_sul co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_rio_grande_do_sul DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_rio_grande_do_sul RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_rio_grande_do_sul ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_rio_grande_do_sul SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_rio_grande_do_sul ADD CONSTRAINT traditional_claims_rio_grande_do_sul_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_rio_grande_do_sul_geom_gix ON outputs.traditional_claims_rio_grande_do_sul USING GIST (geom);
ANALYZE outputs.traditional_claims_rio_grande_do_sul;


-- Rondônia 


DROP TABLE IF EXISTS outputs.traditional_claims_rondonia;

CREATE TABLE outputs.traditional_claims_rondonia AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 22
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_rondonia co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_rondonia DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_rondonia RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_rondonia ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_rondonia SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_rondonia ADD CONSTRAINT traditional_claims_rondonia_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_rondonia_geom_gix ON outputs.traditional_claims_rondonia USING GIST (geom);
ANALYZE outputs.traditional_claims_rondonia;


-- Roraima 


DROP TABLE IF EXISTS outputs.traditional_claims_roraima;

CREATE TABLE outputs.traditional_claims_roraima AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 23
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_roraima co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_roraima DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_roraima RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_roraima ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_roraima SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_roraima ADD CONSTRAINT traditional_claims_roraima_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_roraima_geom_gix ON outputs.traditional_claims_roraima USING GIST (geom);
ANALYZE outputs.traditional_claims_roraima;


-- Santa Catarina 


DROP TABLE IF EXISTS outputs.traditional_claims_santa_catarina;

CREATE TABLE outputs.traditional_claims_santa_catarina AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 24
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_santa_catarina co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_santa_catarina DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_santa_catarina RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_santa_catarina ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_santa_catarina SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_santa_catarina ADD CONSTRAINT traditional_claims_santa_catarina_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_santa_catarina_geom_gix ON outputs.traditional_claims_santa_catarina USING GIST (geom);
ANALYZE outputs.traditional_claims_santa_catarina;


-- São Paulo 


DROP TABLE IF EXISTS outputs.traditional_claims_sao_paulo;

CREATE TABLE outputs.traditional_claims_sao_paulo AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 25
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_sao_paulo co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_sao_paulo DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_sao_paulo RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_sao_paulo ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_sao_paulo SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_sao_paulo ADD CONSTRAINT traditional_claims_sao_paulo_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_sao_paulo_geom_gix ON outputs.traditional_claims_sao_paulo USING GIST (geom);
ANALYZE outputs.traditional_claims_sao_paulo;


-- Sergipe 


DROP TABLE IF EXISTS outputs.traditional_claims_sergipe;

CREATE TABLE outputs.traditional_claims_sergipe AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 26
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_sergipe co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_sergipe DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_sergipe RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_sergipe ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_sergipe SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_sergipe ADD CONSTRAINT traditional_claims_sergipe_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_sergipe_geom_gix ON outputs.traditional_claims_sergipe USING GIST (geom);
ANALYZE outputs.traditional_claims_sergipe;


-- Tocantins


DROP TABLE IF EXISTS outputs.traditional_claims_tocantins;

CREATE TABLE outputs.traditional_claims_tocantins AS
WITH plm_fix AS (
  SELECT ST_Buffer(ST_MakeValid(geom),0) AS plm_geom_fix
  FROM outputs.public_land_merged
  WHERE id = 27
  LIMIT 1
),
co_fix AS (
  SELECT co.*,
         ST_Multi(ST_CollectionExtract(ST_Buffer(ST_MakeValid(co.geom),0),3)) AS geom_fix
  FROM outputs.car_only_tocantins co
  WHERE co.tipo_imove IN ('AST','PCT')
    AND co.geom IS NOT NULL AND NOT ST_IsEmpty(co.geom)
)
SELECT cf.*
FROM co_fix cf CROSS JOIN plm_fix p
WHERE cf.geom_fix IS NOT NULL AND NOT ST_IsEmpty(cf.geom_fix)
  AND ST_Area(cf.geom_fix) > 0
  AND COALESCE(ST_Area(ST_CollectionExtract(ST_Intersection(cf.geom_fix,p.plm_geom_fix),3)),0)
      <= 0.01 * ST_Area(cf.geom_fix);

ALTER TABLE outputs.traditional_claims_tocantins DROP COLUMN geom;
ALTER TABLE outputs.traditional_claims_tocantins RENAME COLUMN geom_fix TO geom;
ALTER TABLE outputs.traditional_claims_tocantins ADD COLUMN IF NOT EXISTS compliance_level integer;
UPDATE outputs.traditional_claims_tocantins SET compliance_level = NULL;
ALTER TABLE outputs.traditional_claims_tocantins ADD CONSTRAINT traditional_claims_tocantins_pkey PRIMARY KEY (id);
CREATE INDEX traditional_claims_tocantins_geom_gix ON outputs.traditional_claims_tocantins USING GIST (geom);
ANALYZE outputs.traditional_claims_tocantins;

end;
-------------------------------------------------
-- BLOCK 24 : aggregated into one single layer --
-------------------------------------------------
begin;

DROP TABLE IF EXISTS outputs.traditional_claims_merged;

CREATE TABLE outputs.traditional_claims_merged AS
SELECT * FROM outputs.traditional_claims_acre
UNION ALL SELECT * FROM outputs.traditional_claims_alagoas
UNION ALL SELECT * FROM outputs.traditional_claims_amapa
UNION ALL SELECT * FROM outputs.traditional_claims_amazonas
UNION ALL SELECT * FROM outputs.traditional_claims_bahia
UNION ALL SELECT * FROM outputs.traditional_claims_ceara
UNION ALL SELECT * FROM outputs.traditional_claims_distrito_federal
UNION ALL SELECT * FROM outputs.traditional_claims_espirito_santo
UNION ALL SELECT * FROM outputs.traditional_claims_goias
UNION ALL SELECT * FROM outputs.traditional_claims_maranhao
UNION ALL SELECT * FROM outputs.traditional_claims_mato_grosso
UNION ALL SELECT * FROM outputs.traditional_claims_mato_grosso_do_sul
UNION ALL SELECT * FROM outputs.traditional_claims_minas_gerais
UNION ALL SELECT * FROM outputs.traditional_claims_para
UNION ALL SELECT * FROM outputs.traditional_claims_paraiba
UNION ALL SELECT * FROM outputs.traditional_claims_parana
UNION ALL SELECT * FROM outputs.traditional_claims_pernambuco
UNION ALL SELECT * FROM outputs.traditional_claims_piaui
UNION ALL SELECT * FROM outputs.traditional_claims_rio_de_janeiro
UNION ALL SELECT * FROM outputs.traditional_claims_rio_grande_do_norte
UNION ALL SELECT * FROM outputs.traditional_claims_rio_grande_do_sul
UNION ALL SELECT * FROM outputs.traditional_claims_rondonia
UNION ALL SELECT * FROM outputs.traditional_claims_roraima
UNION ALL SELECT * FROM outputs.traditional_claims_santa_catarina
UNION ALL SELECT * FROM outputs.traditional_claims_sao_paulo
UNION ALL SELECT * FROM outputs.traditional_claims_sergipe
UNION ALL SELECT * FROM outputs.traditional_claims_tocantins
;

-- Add a new PK (recommended) because id likely repeats across states
ALTER TABLE outputs.traditional_claims_merged
  ADD COLUMN tc_pk bigserial;

ALTER TABLE outputs.traditional_claims_merged
  ADD CONSTRAINT traditional_claims_merged_pkey PRIMARY KEY (tc_pk);

-- Spatial index
CREATE INDEX traditional_claims_merged_geom_gix
  ON outputs.traditional_claims_merged
  USING GIST (geom);

ANALYZE outputs.traditional_claims_merged;

-- set the compliance level
UPDATE outputs.traditional_claims_merged
SET compliance_level = 8;
end;
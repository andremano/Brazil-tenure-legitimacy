-- Queries developed by Andre da Silva Mano | a.dasilvamano[at]utwente.nl | 2025

----------------------------------------------
-- BLOCK 22 : All the public land aggregated--
----------------------------------------------


-----------------------------
-- Public Land of Amazonas --
-----------------------------
begin;


/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Amazonas';   -- <<< CHANGE THIS

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM uf;
  IF n <> 1 THEN
    RAISE EXCEPTION 'Expected exactly 1 UF row for nm_uf, got %', n;
  END IF;
END $$;

CREATE INDEX ON uf USING GIST (geom_fix);

-- Clip each public land layer (and enforcing geometry validity)

/* uncomment this block if outputs.base_map is to be included
DROP TABLE IF EXISTS clip_base_map;
CREATE TEMP TABLE clip_base_map AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.base_map t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix); 	*/

DROP TABLE IF EXISTS clip_assentamentos;
CREATE TEMP TABLE clip_assentamentos AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.assentamentos t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_assentamentos_reconhecimento;
CREATE TEMP TABLE clip_assentamentos_reconhecimento AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.assentamentos_reconhecimento t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_ccdru;
CREATE TEMP TABLE clip_quilombolas_ccdru AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_ccdru t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_decreto;
CREATE TEMP TABLE clip_quilombolas_decreto AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_decreto t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_estatuto_indeterminado;
CREATE TEMP TABLE clip_quilombolas_estatuto_indeterminado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_estatuto_indeterminado t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_parcialmente_titulado;
CREATE TEMP TABLE clip_quilombolas_parcialmente_titulado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_parcialmente_titulados t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_portaria;
CREATE TEMP TABLE clip_quilombolas_portaria AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_portaria t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_rtid;
CREATE TEMP TABLE clip_quilombolas_rtid AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_rtid t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_titulados;
CREATE TEMP TABLE clip_quilombolas_titulados AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_titulados t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_titulo_anulado;
CREATE TEMP TABLE clip_quilombolas_titulo_anulado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_titulo_anulado t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares;
CREATE TEMP TABLE clip_areas_militares AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares_compiladas;
CREATE TEMP TABLE clip_areas_militares_compiladas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares_compiladas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares_reconstituidas;
CREATE TEMP TABLE clip_areas_militares_reconstituidas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares_reconstituidas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_a;
CREATE TEMP TABLE clip_uc_a AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs."uc_A" t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_b;
CREATE TEMP TABLE clip_uc_b AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs."uc_B" t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_environmental_protection_areas;
CREATE TEMP TABLE clip_uc_environmental_protection_areas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.uc_environmental_protection_areas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_uso_sustentavel;
CREATE TEMP TABLE clip_uc_uso_sustentavel AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.uc_uso_sustentavel t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_terra_indigena;
CREATE TEMP TABLE clip_terra_indigena AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.terra_indigena t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);

-- Union into single geometry

DROP TABLE IF EXISTS outputs.public_land_amazonas;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_amazonas AS -- <<< CHANGE NAME
WITH all_clipped AS (
  /*SELECT geom FROM clip_base_map
  UNION ALL SELECT geom FROM assentamentos */ -- <<< Uncomment if outputs_base_map is to be included.
  SELECT geom FROM clip_assentamentos  -- <<< Delete Uncomment if outputs_base_map is to be included.
  UNION ALL SELECT geom FROM clip_assentamentos_reconhecimento
  UNION ALL SELECT geom FROM clip_quilombolas_ccdru
  UNION ALL SELECT geom FROM clip_quilombolas_decreto
  UNION ALL SELECT geom FROM clip_quilombolas_estatuto_indeterminado
  UNION ALL SELECT geom FROM clip_quilombolas_parcialmente_titulado
  UNION ALL SELECT geom FROM clip_quilombolas_portaria
  UNION ALL SELECT geom FROM clip_quilombolas_rtid
  UNION ALL SELECT geom FROM clip_quilombolas_titulados
  UNION ALL SELECT geom FROM clip_quilombolas_titulo_anulado
  UNION ALL SELECT geom FROM clip_areas_militares
  UNION ALL SELECT geom FROM clip_areas_militares_compiladas
  UNION ALL SELECT geom FROM clip_areas_militares_reconstituidas
  UNION ALL SELECT geom FROM clip_uc_a
  UNION ALL SELECT geom FROM clip_uc_b
  UNION ALL SELECT geom FROM clip_uc_environmental_protection_areas
  UNION ALL SELECT geom FROM clip_uc_uso_sustentavel
  UNION ALL SELECT geom FROM clip_terra_indigena
),
u AS (
  SELECT ST_Multi(
           ST_UnaryUnion(
             ST_CollectionExtract(
               ST_MakeValid(ST_Collect(geom)),
               3
             )
           )
         ) AS geom_union
  FROM all_clipped
  WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)
)
SELECT (SELECT nm_uf FROM uf) AS nm_uf,
       u.geom_union AS geom
FROM u;


CREATE INDEX public_land_amazonas_gix   -- <<< CHANGE NAME
ON outputs.public_land_amazonas   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_amazonas;

end;

--------------------------
-- PUBLIC LAND OF AMAPA --
--------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Amapá';   -- <<< CHANGE THIS

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM uf;
  IF n <> 1 THEN
    RAISE EXCEPTION 'Expected exactly 1 UF row for nm_uf, got %', n;
  END IF;
END $$;

CREATE INDEX ON uf USING GIST (geom_fix);

-- Clip each public land layer (and enforcing geometry validity)

/* uncomment this block if outputs.base_map is to be included
DROP TABLE IF EXISTS clip_base_map;
CREATE TEMP TABLE clip_base_map AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.base_map t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix); 	*/

DROP TABLE IF EXISTS clip_assentamentos;
CREATE TEMP TABLE clip_assentamentos AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.assentamentos t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_assentamentos_reconhecimento;
CREATE TEMP TABLE clip_assentamentos_reconhecimento AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.assentamentos_reconhecimento t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_ccdru;
CREATE TEMP TABLE clip_quilombolas_ccdru AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_ccdru t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_decreto;
CREATE TEMP TABLE clip_quilombolas_decreto AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_decreto t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_estatuto_indeterminado;
CREATE TEMP TABLE clip_quilombolas_estatuto_indeterminado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_estatuto_indeterminado t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_parcialmente_titulado;
CREATE TEMP TABLE clip_quilombolas_parcialmente_titulado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_parcialmente_titulados t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_portaria;
CREATE TEMP TABLE clip_quilombolas_portaria AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_portaria t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_rtid;
CREATE TEMP TABLE clip_quilombolas_rtid AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_rtid t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_titulados;
CREATE TEMP TABLE clip_quilombolas_titulados AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_titulados t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_titulo_anulado;
CREATE TEMP TABLE clip_quilombolas_titulo_anulado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_titulo_anulado t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares;
CREATE TEMP TABLE clip_areas_militares AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares_compiladas;
CREATE TEMP TABLE clip_areas_militares_compiladas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares_compiladas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares_reconstituidas;
CREATE TEMP TABLE clip_areas_militares_reconstituidas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares_reconstituidas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_a;
CREATE TEMP TABLE clip_uc_a AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs."uc_A" t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_b;
CREATE TEMP TABLE clip_uc_b AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs."uc_B" t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_environmental_protection_areas;
CREATE TEMP TABLE clip_uc_environmental_protection_areas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.uc_environmental_protection_areas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_uso_sustentavel;
CREATE TEMP TABLE clip_uc_uso_sustentavel AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.uc_uso_sustentavel t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_terra_indigena;
CREATE TEMP TABLE clip_terra_indigena AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.terra_indigena t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);

-- Union into single geometry

DROP TABLE IF EXISTS outputs.public_land_amapa;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_amapa AS -- <<< CHANGE NAME
WITH all_clipped AS (
  /*SELECT geom FROM clip_base_map
  UNION ALL SELECT geom FROM assentamentos */ -- <<< Uncomment if outputs_base_map is to be included.
  SELECT geom FROM clip_assentamentos  -- <<< Delete Uncomment if outputs_base_map is to be included.
  UNION ALL SELECT geom FROM clip_assentamentos_reconhecimento
  UNION ALL SELECT geom FROM clip_quilombolas_ccdru
  UNION ALL SELECT geom FROM clip_quilombolas_decreto
  UNION ALL SELECT geom FROM clip_quilombolas_estatuto_indeterminado
  UNION ALL SELECT geom FROM clip_quilombolas_parcialmente_titulado
  UNION ALL SELECT geom FROM clip_quilombolas_portaria
  UNION ALL SELECT geom FROM clip_quilombolas_rtid
  UNION ALL SELECT geom FROM clip_quilombolas_titulados
  UNION ALL SELECT geom FROM clip_quilombolas_titulo_anulado
  UNION ALL SELECT geom FROM clip_areas_militares
  UNION ALL SELECT geom FROM clip_areas_militares_compiladas
  UNION ALL SELECT geom FROM clip_areas_militares_reconstituidas
  UNION ALL SELECT geom FROM clip_uc_a
  UNION ALL SELECT geom FROM clip_uc_b
  UNION ALL SELECT geom FROM clip_uc_environmental_protection_areas
  UNION ALL SELECT geom FROM clip_uc_uso_sustentavel
  UNION ALL SELECT geom FROM clip_terra_indigena
),
u AS (
  SELECT ST_Multi(
           ST_UnaryUnion(
             ST_CollectionExtract(
               ST_MakeValid(ST_Collect(geom)),
               3
             )
           )
         ) AS geom_union
  FROM all_clipped
  WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)
)
SELECT (SELECT nm_uf FROM uf) AS nm_uf,
       u.geom_union AS geom
FROM u;


CREATE INDEX public_land_amapa_gix   -- <<< CHANGE NAME
ON outputs.public_land_amapa   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_amapa; -- <<< CHANGE NAME

end;
--------------------------------------
-- Public Land for Distrito Federal --
--------------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Distrito Federal';   -- <<< CHANGE THIS

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM uf;
  IF n <> 1 THEN
    RAISE EXCEPTION 'Expected exactly 1 UF row for nm_uf, got %', n;
  END IF;
END $$;

CREATE INDEX ON uf USING GIST (geom_fix);

-- Clip each public land layer (and enforcing geometry validity)

/* uncomment this block if outputs.base_map is to be included
DROP TABLE IF EXISTS clip_base_map;
CREATE TEMP TABLE clip_base_map AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.base_map t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix); 	*/

DROP TABLE IF EXISTS clip_assentamentos;
CREATE TEMP TABLE clip_assentamentos AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.assentamentos t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_assentamentos_reconhecimento;
CREATE TEMP TABLE clip_assentamentos_reconhecimento AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.assentamentos_reconhecimento t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_ccdru;
CREATE TEMP TABLE clip_quilombolas_ccdru AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_ccdru t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_decreto;
CREATE TEMP TABLE clip_quilombolas_decreto AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_decreto t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_estatuto_indeterminado;
CREATE TEMP TABLE clip_quilombolas_estatuto_indeterminado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_estatuto_indeterminado t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_parcialmente_titulado;
CREATE TEMP TABLE clip_quilombolas_parcialmente_titulado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_parcialmente_titulados t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_portaria;
CREATE TEMP TABLE clip_quilombolas_portaria AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_portaria t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_rtid;
CREATE TEMP TABLE clip_quilombolas_rtid AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_rtid t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_titulados;
CREATE TEMP TABLE clip_quilombolas_titulados AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_titulados t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_titulo_anulado;
CREATE TEMP TABLE clip_quilombolas_titulo_anulado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_titulo_anulado t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares;
CREATE TEMP TABLE clip_areas_militares AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares_compiladas;
CREATE TEMP TABLE clip_areas_militares_compiladas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares_compiladas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares_reconstituidas;
CREATE TEMP TABLE clip_areas_militares_reconstituidas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares_reconstituidas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_a;
CREATE TEMP TABLE clip_uc_a AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs."uc_A" t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_b;
CREATE TEMP TABLE clip_uc_b AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs."uc_B" t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_environmental_protection_areas;
CREATE TEMP TABLE clip_uc_environmental_protection_areas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.uc_environmental_protection_areas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_uso_sustentavel;
CREATE TEMP TABLE clip_uc_uso_sustentavel AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.uc_uso_sustentavel t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_terra_indigena;
CREATE TEMP TABLE clip_terra_indigena AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.terra_indigena t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);

-- Union into single geometry

DROP TABLE IF EXISTS outputs.public_land_distrito_federal;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_distrito_federal AS -- <<< CHANGE NAME
WITH all_clipped AS (
  /*SELECT geom FROM clip_base_map
  UNION ALL SELECT geom FROM assentamentos */ -- <<< Uncomment if outputs_base_map is to be included.
  SELECT geom FROM clip_assentamentos  -- <<< Delete Uncomment if outputs_base_map is to be included.
  UNION ALL SELECT geom FROM clip_assentamentos_reconhecimento
  UNION ALL SELECT geom FROM clip_quilombolas_ccdru
  UNION ALL SELECT geom FROM clip_quilombolas_decreto
  UNION ALL SELECT geom FROM clip_quilombolas_estatuto_indeterminado
  UNION ALL SELECT geom FROM clip_quilombolas_parcialmente_titulado
  UNION ALL SELECT geom FROM clip_quilombolas_portaria
  UNION ALL SELECT geom FROM clip_quilombolas_rtid
  UNION ALL SELECT geom FROM clip_quilombolas_titulados
  UNION ALL SELECT geom FROM clip_quilombolas_titulo_anulado
  UNION ALL SELECT geom FROM clip_areas_militares
  UNION ALL SELECT geom FROM clip_areas_militares_compiladas
  UNION ALL SELECT geom FROM clip_areas_militares_reconstituidas
  UNION ALL SELECT geom FROM clip_uc_a
  UNION ALL SELECT geom FROM clip_uc_b
  UNION ALL SELECT geom FROM clip_uc_environmental_protection_areas
  UNION ALL SELECT geom FROM clip_uc_uso_sustentavel
  UNION ALL SELECT geom FROM clip_terra_indigena
),
u AS (
  SELECT ST_Multi(
           ST_UnaryUnion(
             ST_CollectionExtract(
               ST_MakeValid(ST_Collect(geom)),
               3
             )
           )
         ) AS geom_union
  FROM all_clipped
  WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)
)
SELECT (SELECT nm_uf FROM uf) AS nm_uf,
       u.geom_union AS geom
FROM u;


CREATE INDEX public_land_distrito_federal_gix   -- <<< CHANGE NAME
ON outputs.public_land_distrito_federal   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_distrito_federal; -- <<< CHANGE NAME

end;
--------------------------------------
-- Public Land for Distrito Alagoas --
--------------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Alagoas';   -- <<< CHANGE THIS

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM uf;
  IF n <> 1 THEN
    RAISE EXCEPTION 'Expected exactly 1 UF row for nm_uf, got %', n;
  END IF;
END $$;

CREATE INDEX ON uf USING GIST (geom_fix);

-- Clip each public land layer (and enforcing geometry validity)

/* uncomment this block if outputs.base_map is to be included
DROP TABLE IF EXISTS clip_base_map;
CREATE TEMP TABLE clip_base_map AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.base_map t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix); 	*/

DROP TABLE IF EXISTS clip_assentamentos;
CREATE TEMP TABLE clip_assentamentos AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.assentamentos t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_assentamentos_reconhecimento;
CREATE TEMP TABLE clip_assentamentos_reconhecimento AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.assentamentos_reconhecimento t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_ccdru;
CREATE TEMP TABLE clip_quilombolas_ccdru AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_ccdru t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_decreto;
CREATE TEMP TABLE clip_quilombolas_decreto AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_decreto t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_estatuto_indeterminado;
CREATE TEMP TABLE clip_quilombolas_estatuto_indeterminado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_estatuto_indeterminado t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_parcialmente_titulado;
CREATE TEMP TABLE clip_quilombolas_parcialmente_titulado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_parcialmente_titulados t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_portaria;
CREATE TEMP TABLE clip_quilombolas_portaria AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_portaria t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_rtid;
CREATE TEMP TABLE clip_quilombolas_rtid AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_rtid t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_titulados;
CREATE TEMP TABLE clip_quilombolas_titulados AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_titulados t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_quilombolas_titulo_anulado;
CREATE TEMP TABLE clip_quilombolas_titulo_anulado AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.quilombolas_titulo_anulado t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares;
CREATE TEMP TABLE clip_areas_militares AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares_compiladas;
CREATE TEMP TABLE clip_areas_militares_compiladas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares_compiladas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_areas_militares_reconstituidas;
CREATE TEMP TABLE clip_areas_militares_reconstituidas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.areas_militares_reconstituidas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_a;
CREATE TEMP TABLE clip_uc_a AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs."uc_A" t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_b;
CREATE TEMP TABLE clip_uc_b AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs."uc_B" t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_environmental_protection_areas;
CREATE TEMP TABLE clip_uc_environmental_protection_areas AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.uc_environmental_protection_areas t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_uc_uso_sustentavel;
CREATE TEMP TABLE clip_uc_uso_sustentavel AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.uc_uso_sustentavel t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);


DROP TABLE IF EXISTS clip_terra_indigena;
CREATE TEMP TABLE clip_terra_indigena AS
SELECT ST_CollectionExtract(
         ST_Intersection(ST_Buffer(ST_MakeValid(t.geom),0), uf.geom_fix),
         3
       ) AS geom
FROM outputs.terra_indigena t
JOIN uf ON t.geom && uf.geom_fix AND ST_Intersects(t.geom, uf.geom_fix);

-- Union into single geometry

DROP TABLE IF EXISTS outputs.public_land_alagoas;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_alagoas AS -- <<< CHANGE NAME
WITH all_clipped AS (
  /*SELECT geom FROM clip_base_map
  UNION ALL SELECT geom FROM assentamentos */ -- <<< Uncomment if outputs_base_map is to be included.
  SELECT geom FROM clip_assentamentos  -- <<< Delete Uncomment if outputs_base_map is to be included.
  UNION ALL SELECT geom FROM clip_assentamentos_reconhecimento
  UNION ALL SELECT geom FROM clip_quilombolas_ccdru
  UNION ALL SELECT geom FROM clip_quilombolas_decreto
  UNION ALL SELECT geom FROM clip_quilombolas_estatuto_indeterminado
  UNION ALL SELECT geom FROM clip_quilombolas_parcialmente_titulado
  UNION ALL SELECT geom FROM clip_quilombolas_portaria
  UNION ALL SELECT geom FROM clip_quilombolas_rtid
  UNION ALL SELECT geom FROM clip_quilombolas_titulados
  UNION ALL SELECT geom FROM clip_quilombolas_titulo_anulado
  UNION ALL SELECT geom FROM clip_areas_militares
  UNION ALL SELECT geom FROM clip_areas_militares_compiladas
  UNION ALL SELECT geom FROM clip_areas_militares_reconstituidas
  UNION ALL SELECT geom FROM clip_uc_a
  UNION ALL SELECT geom FROM clip_uc_b
  UNION ALL SELECT geom FROM clip_uc_environmental_protection_areas
  UNION ALL SELECT geom FROM clip_uc_uso_sustentavel
  UNION ALL SELECT geom FROM clip_terra_indigena
),
u AS (
  SELECT ST_Multi(
           ST_UnaryUnion(
             ST_CollectionExtract(
               ST_MakeValid(ST_Collect(geom)),
               3
             )
           )
         ) AS geom_union
  FROM all_clipped
  WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)
)
SELECT (SELECT nm_uf FROM uf) AS nm_uf,
       u.geom_union AS geom
FROM u;


CREATE INDEX public_land_alagoas_gix   -- <<< CHANGE NAME
ON outputs.public_land_alagoas   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_alagoas; -- <<< CHANGE NAME

end;
-- Queries by Andre da Silva Mano | a.dasilvamano[at]utwente.nl

--------------------------
-- BLOCK 0: PREPARATION --
--------------------------

	/*
	The queries assume the use of PostgreSQL >16 and PostGIS >3.3

	Create a custom SRS to have support comparable area measurements for all of Brazil.
	This is done by creating a System based on the Dataum SIRGAS 2000 and an Albers Equal Area Projection as recommended by the Instituto Brasileiro de Geografia e Estatística (IBGE)
	Reference: Instituto Brasileiro de Geografia e Estatística – Diretoria de Pesquisas, Coordenação de Estruturas Territoriais 
			   Malha Municipal Digital e Áreas Territoriais 2024 - Notas metodológicas
			   Rio de Janeiro, 2025
			   https://biblioteca.ibge.gov.br/visualizacao/livros/liv102169.pdf (assessed 12 September, 2025)
	*/


	INSERT INTO spatial_ref_sys (srid, auth_name, auth_srid, proj4text, srtext)
	VALUES (
	  900915,
	  'CUSTOM',
	  900915,
	  '+proj=aea +lat_0=-12 +lon_0=-54 +lat_1=-2 +lat_2=-22 +x_0=5000000 +y_0=10000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs +type=crs',
	  'BOUNDCRS[SOURCECRS[PROJCRS["unknown",BASEGEOGCRS["unknown",DATUM["Unknown based on GRS 1980 ellipsoid using towgs84=0,0,0,0,0,0,0",ELLIPSOID["GRS 1980",6378137,298.257222101,LENGTHUNIT["metre",1],ID["EPSG",7019]]],PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8901]]],CONVERSION["unknown",METHOD["Albers Equal Area",ID["EPSG",9822]],PARAMETER["Latitude of false origin",-12,ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8821]],PARAMETER["Longitude of false origin",-54,ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8822]],PARAMETER["Latitude of 1st standard parallel",-2,ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8823]],PARAMETER["Latitude of 2nd standard parallel",-22,ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8824]],PARAMETER["Easting at false origin",5000000,LENGTHUNIT["metre",1],ID["EPSG",8826]],PARAMETER["Northing at false origin",10000000,LENGTHUNIT["metre",1],ID["EPSG",8827]]],CS[Cartesian,2],AXIS["(E)",east,ORDER[1],LENGTHUNIT["metre",1,ID["EPSG",9001]]],AXIS["(N)",north,ORDER[2],LENGTHUNIT["metre",1,ID["EPSG",9001]]]]'
	);


-----------------------------------------------
-- BLOCK 1: THE BASE MAP --
-----------------------------------------------


	/*
	The base map represents areas where private (rural) tenure rights should not apply. It is made by merging 5 datasets:
	
	 1 - areas_urbanizadas_2019
	 2 - massas_agua
	 3 - estradas_federais (a 15m buffer is applyed)
	 4 - estradas_estaduais (a 10m buffer is applyed)
	 5 - ferrovias (a 15m buffer is applyed)
	
	*/

		begin;	
			
			CREATE TABLE outputs.base_map AS
			SELECT ROW_NUMBER() OVER (ORDER BY layer_name, geom)::int AS id,
				   geom,
				   layer_name,
				   ST_Area(geom) AS area_m2,
				   ST_Area(geom) / 10000.0 AS area_ha,
				   ST_Area(geom) / 1000000.0 AS area_km2
			FROM (
				SELECT 
					(ST_Dump(ST_Union(geom))).geom AS geom,
					layer_name
				FROM (
					-- 1. Urban areas
					SELECT geom, 'urban_areas' AS layer_name 
					FROM raw_data.areas_urbanizadas_2019
					
					UNION ALL
					
					-- 2. Water bodies
					SELECT geom, 'water_bodies' AS layer_name 
					FROM raw_data.massas_agua
					
					UNION ALL
					
					-- 3. Federal roads buffered to 15 m
					SELECT ST_Buffer(geom, 15) AS geom, 'federal_roads' AS layer_name 
					FROM raw_data.estradas_federais
					
					UNION ALL
					
					-- 4. State roads buffered to 10 m
					SELECT ST_Buffer(geom, 10) AS geom, 'state_roads' AS layer_name 
					FROM raw_data.estradas_estaduais
					
					UNION ALL
					
					-- 5. Railways buffered to 15 m
					SELECT ST_Buffer(geom, 15) AS geom, 'railways' AS layer_name 
					FROM raw_data.ferrovias
				) AS all_geoms
				GROUP BY layer_name
			) AS base_map;


			-- create PK
			ALTER TABLE outputs.base_map
			ADD CONSTRAINT merged_geometry_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('merged_geometry'::regclass);

		end;


----------------------------------------------------
-- BLOCK 2: INDIGENOUS LAND --
----------------------------------------------------


	/*
	The indigenous land map - "terra_indigena", is made from unioning 4 layers representing different status of indigenous land:
	
	 1 - ti_homologada
	 2 - ti_nao_homologada
	 3 - ti_dominial
	 4 - ti_reserva

	*/

		begin;

			CREATE TABLE outputs.terra_indigena AS 

			(SELECT *
				FROM raw_data.ti_dominial

			UNION 

			SELECT * 
				FROM raw_data.ti_homologada

			UNION 

			SELECT *
				FROM raw_data.ti_nao_homologada

			UNION 

			SELECT *
				FROM raw_data.ti_reserva);

			-- make sure the  'id' column is unique
			UPDATE outputs.terra_indigena AS ti
			SET id = s.rn
				FROM (
				SELECT ctid, row_number() OVER () AS rn
				FROM outputs.terra_indigena) AS s
			WHERE ti.ctid = s.ctid;

			-- Add Primary Key
			ALTER TABLE outputs.terra_indigena
			ADD CONSTRAINT terraindigena_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.terra_indigena'::regclass);

			ALTER TABLE outputs.terra_indigena
			DROP COLUMN epsg;

		end;


-----------------------------------------------------------
-- BLOCK 3: CONSERVATION UNITS --
----------------------------------------------------------


	/*
	The conservation units map - "unidades de conservacão", is made from filtering by category the conservation units dataset. Check the WHERE clause)
	*/


-- conservation units of integral protection (A)


		begin;

			CREATE TABLE outputs.uc_A AS 
			(SELECT * FROM raw_data.unidades_conservacao
			WHERE categoria IN ( 'Estação Ecológica', 'Parque', 'Reserva Biológica'));

			-- Add Primary Key
			ALTER TABLE outputs.uc_A
			ADD CONSTRAINT uc_A_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.uc_A'::regclass);

			-- Create spatial index

			CREATE INDEX idx_uc_A_geom ON outputs.uc_A USING GIST ( geom );

		end;


-- conservation units of integral protection (B)


		begin;

			CREATE TABLE outputs.uc_B AS 
			(SELECT * FROM raw_data.unidades_conservacao
			WHERE categoria IN ( 'Refúgio de Vida Silvestre', 'Monumento Natural'));

			-- Add Primary Key
			ALTER TABLE outputs.uc_B
			ADD CONSTRAINT uc_B_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.uc_B'::regclass);

			-- Create spatial index

			CREATE INDEX idx_uc_B_geom ON outputs.uc_B USING GIST ( geom );

		end;


-- conservation units of sustainable use



		begin;

			CREATE TABLE outputs.uc_uso_sustentavel AS 
			(SELECT * FROM raw_data.unidades_conservacao
			WHERE categoria IN ( 'Área de Relevante Interesse Ecológico', 'Floresta', 'Reserva de Desenvolvimento Sustentável', 'Reserva Extrativista'));

			-- Add Primary Key
			ALTER TABLE outputs.uc_uso_sustentavel
			ADD CONSTRAINT uc_uso_sustentaval_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.uc_uso_sustentavel'::regclass);

			-- Create spatial index

			CREATE INDEX idx_uc_uso_sustentaval_geom ON outputs.uc_uso_sustentavel USING GIST ( geom );

		end;


-- environmental protection areas



		begin;

			CREATE TABLE outputs.uc_environmental_protection_areas AS 
			(SELECT * FROM raw_data.unidades_conservacao
			WHERE categoria IN ( 'Área de Proteção Ambiental'));

			-- Add Primary Key
			ALTER TABLE outputs.uc_environmental_protection_areas
			ADD CONSTRAINT uc_environmental_protection_areas_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.uc_environmental_protection_areas'::regclass);

			-- Create spatial index

			CREATE INDEX idx_uc_environmental_protection_areas_geom ON outputs.uc_environmental_protection_areas USING GIST ( geom );

		end;




--------------------------------------------------
-- BLOCK 4: MILITARY AREAS --
-------------------------------------------------


	/*
	The military areas maps - "areas_militares", are made into a PostgreSQL views from filtering by attribute. Check the WHERE clause)
	*/


		begin;

		-- Compiled military areas (view definition)

			CREATE VIEW outputs.areas_militares_compiladas as
			SELECT gid, nm_nome, cd_sigla, cd_adminis, md_ar_poli, data_alter, metodo_alt, fonte_info, geom
			FROM raw_data.areas_militares
			WHERE metodo_alt = 'Compilação';


			-- Compiled military areas (view definition)


			CREATE VIEW outputs.areas_militares_reconstituidas as

			SELECT gid, nm_nome, cd_sigla, cd_adminis, md_ar_poli, data_alter, metodo_alt, fonte_info, geom
			FROM raw_data.areas_militares
			WHERE metodo_alt = 'RECONTITUIÇÃO';

		end;




----------------------------------------
-- BLOCK 5: Quilombolas --
----------------------------------------


	/*
	The quilombolas maps - "quilombolas_x", are made into PostgreSQL views from filtering by attribute. Check the WHERE clause)
	*/


		begin;


		-- Titled quilombolas (view definition)

			CREATE VIEW outputs.quilombolas_titulados as
			SELECT *
			FROM raw_data.quilombolas
			WHERE fase= 'TITULADO';


		-- Partially titled quilombolas (view definition)


			CREATE VIEW outputs.quilombolas_parcialmente_titulados as
			SELECT *
			FROM raw_data.quilombolas
			WHERE fase = 'TITULO PARCIAL';


		-- Partially titled quilombolas (view definition)

			CREATE VIEW outputs.quilombolas_decreto as
			SELECT *
			FROM raw_data.quilombolas
			WHERE fase = 'DECRETO';


		-- Quilombolas in decree phase (view definition)


			CREATE VIEW outputs.quilombolas_portaria as
			SELECT *
			FROM raw_data.quilombolas
			WHERE fase = 'PORTARIA';


		-- Quilombolas in RTDI phase (view definition)

			CREATE VIEW outputs.quilombolas_rtid as
			SELECT *
			FROM raw_data.quilombolas
			WHERE fase = 'RTID';


		-- Quilombolas in CCDRU phase (view definition)

			CREATE VIEW outputs.quilombolas_ccdru as
			SELECT *
			FROM raw_data.quilombolas
			WHERE fase = 'CCDRU';


		-- Quilombolas with revoked title (view definition)

			CREATE VIEW outputs.quilombolas_titulo_anulado as
			SELECT *
			FROM raw_data.quilombolas
			WHERE fase = 'TITULO ANULADO';


		-- Quilombolas with undetermined status (view definition)

			CREATE VIEW outputs.quilombolas_estatuto_indeterminado as
			SELECT *
			FROM raw_data.quilombolas
			WHERE fase IS NULL;

		end;


----------------------------------------------
-- BLOCK 6 : All the public land aggregated---
----------------------------------------------

/*This layer represents the union of all public land geometries. It is intended for identifying whether an area falls under any form of public 
  or collective land right. The table does not distinguish between specific public land categories */


-----------------------------
-- Public land of Amazonas --
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

----------------------------
-- Public Land of Alagoas --
----------------------------
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
-------------------------
-- Public Land of Acre --
-------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Acre';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_acre;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_acre AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_acre_gix   -- <<< CHANGE NAME
ON outputs.public_land_acre   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_acre; -- <<< CHANGE NAME

end;
-----------------------------
-- Public land of Bahia --
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
WHERE nm_uf = 'Bahia';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_bahia;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_bahia AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_bahia_gix   -- <<< CHANGE NAME
ON outputs.public_land_bahia   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_bahia; -- <<< CHANGE NAME

end;
-----------------------------
-- Public land of Ceará --
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
WHERE nm_uf = 'Ceará';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_ceara;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_ceara AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_ceara_gix   -- <<< CHANGE NAME
ON outputs.public_land_ceara   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_ceara; -- <<< CHANGE NAME

end;
-----------------------------------
-- Public Land of Espírito Santo --
-----------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Espírito Santo';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_espirito_santo;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_espirito_santo AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_espirito_santo_gix   -- <<< CHANGE NAME
ON outputs.public_land_espirito_santo   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_espirito_santo; -- <<< CHANGE NAME

end;
------------------------------------
-- Public land of Distrito Federal --
-------------------------------------
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
--------------------------
-- Public Land of Goiás --
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
WHERE nm_uf = 'Goiás';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_goias;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_goias AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_goias_gix   -- <<< CHANGE NAME
ON outputs.public_land_goias   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_goias; -- <<< CHANGE NAME

end;
-----------------------------
-- Public land of Maranhão --
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
WHERE nm_uf = 'Maranhão';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_maranhao;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_maranhao AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_maranhao_gix   -- <<< CHANGE NAME
ON outputs.public_land_maranhao   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_maranhao; -- <<< CHANGE NAME

end;
---------------------------------
-- Public land of Minas Gerais --
---------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Minas Gerais';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_minas_gerais;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_minas_gerais AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_minas_gerais_gix   -- <<< CHANGE NAME
ON outputs.public_land_minas_gerais   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_minas_gerais; -- <<< CHANGE NAME

end;
--------------------------------
-- Public Land of Mato Grosso --
--------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Mato Grosso';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_mato_grosso;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_mato_grosso AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_mato_grosso_gix   -- <<< CHANGE NAME
ON outputs.public_land_mato_grosso   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_mato_grosso; -- <<< CHANGE NAME

end;
---------------------------------------
-- Public Land of Mato Grosso do Sul --
---------------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Mato Grosso do Sul';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_mato_grosso_do_sul;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_mato_grosso_do_sul AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_mato_grosso_do_sul_gix   -- <<< CHANGE NAME
ON outputs.public_land_mato_grosso_do_sul   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_mato_grosso_do_sul; -- <<< CHANGE NAME

end;
--------------------------
--  Public land of Para --                             --
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
WHERE nm_uf = 'Pará';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_para;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_para AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_para_gix   -- <<< CHANGE NAME
ON outputs.public_land_para   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_para; -- <<< CHANGE NAME

end;
----------------------------
-- Public land of Paraíba --
----------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Paraíba';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_paraiba;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_paraiba AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_paraiba_gix   -- <<< CHANGE NAME
ON outputs.public_land_paraiba   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_paraiba; -- <<< CHANGE NAME

end;
-------------------------------
-- Public land of Pernambuco --
-------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Pernambuco';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_pernambuco;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_pernambuco AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_pernambuco_gix   -- <<< CHANGE NAME
ON outputs.public_land_pernambuco   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_pernambuco; -- <<< CHANGE NAME

end;
---------------------------
-- Public land of Paraná --
---------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Paraná';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_parana;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_parana AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_parana_gix   -- <<< CHANGE NAME
ON outputs.public_land_parana   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_parana; -- <<< CHANGE NAME

end;
--------------------------
-- Public land of Piauí --
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
WHERE nm_uf = 'Piauí';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_piaui;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_piaui AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_piaui_gix   -- <<< CHANGE NAME
ON outputs.public_land_piaui   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_piaui; -- <<< CHANGE NAME

end;
-----------------------------------
-- Public Land of Rio de Janeiro --
-----------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Rio de Janeiro';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_rio_de_janeiro;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_rio_de_janeiro AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_rio_de_janeiro_gix   -- <<< CHANGE NAME
ON outputs.public_land_rio_de_janeiro   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_rio_de_janeiro; -- <<< CHANGE NAME

end;
----------------------------------------
-- Public land of Rio Grande do Norte --
----------------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Rio Grande do Norte';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_rio_grande_do_norte;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_rio_grande_do_norte AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_rio_grande_do_norte_gix   -- <<< CHANGE NAME
ON outputs.public_land_rio_grande_do_norte   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_rio_grande_do_norte; -- <<< CHANGE NAME

end;
-----------------------
-- Rio Grande do Sul --
-----------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Rio Grande do Sul';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_rio_grande_do_sul;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_rio_grande_do_sul AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_rio_grande_do_sul_gix   -- <<< CHANGE NAME
ON outputs.public_land_rio_grande_do_sul   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_rio_grande_do_sul; -- <<< CHANGE NAME

end;
---------------------------
--  Public land Rondônia --
---------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Rondônia';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_rondonia;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_rondonia AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_rondonia_gix   -- <<< CHANGE NAME
ON outputs.public_land_rondonia   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_rondonia; -- <<< CHANGE NAME

end;
----------------------
-- Public land Roraima
----------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Roraima';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_roraima;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_roraima AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_roraima_gix   -- <<< CHANGE NAME
ON outputs.public_land_roraima   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_roraima; -- <<< CHANGE NAME

end; 
-----------------------------------
-- Public land of Santa Catarina --
-----------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Santa Catarina';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_santa_catarina;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_santa_catarina AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_santa_catarina_gix   -- <<< CHANGE NAME
ON outputs.public_land_santa_catarina   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_santa_catarina; -- <<< CHANGE NAME

end;
------------------------------
-- Public land of São Paulo --
------------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'São Paulo';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_sao_paulo;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_sao_paulo AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_sao_paulo_gix   -- <<< CHANGE NAME
ON outputs.public_land_sao_paulo   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_sao_paulo; -- <<< CHANGE NAME

end;
----------------------------
-- Public land of Sergipe --
----------------------------
begin;

/* Materialize and make sure the geometry of the federal unit (i.e. "Estado") is valid. 
This will then be used as an argument of the spatial functions used in the subsequent steps */

DROP TABLE IF EXISTS uf;

CREATE TEMP TABLE uf AS
SELECT
    *,
    ST_Buffer(ST_MakeValid(geom), 0) AS geom_fix
FROM raw_data.brasil_estados
WHERE nm_uf = 'Sergipe';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_sergipe;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_sergipe AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_sergipe_gix   -- <<< CHANGE NAME
ON outputs.public_land_sergipe   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_sergipe; -- <<< CHANGE NAME

end;
-----------------------------
-- Public land of Tocantins --
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
WHERE nm_uf = 'Tocantins';   -- <<< CHANGE THIS

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

DROP TABLE IF EXISTS outputs.public_land_tocantins;  -- <<< CHANGE NAME

CREATE TABLE outputs.public_land_tocantins AS -- <<< CHANGE NAME
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


CREATE INDEX public_land_tocantins_gix   -- <<< CHANGE NAME
ON outputs.public_land_tocantins   -- <<< CHANGE NAME
USING GIST (geom);

ANALYZE outputs.public_land_tocantins; -- <<< CHANGE NAME

end;

---------------------------------------------------------------------
-- BLOCK 7 : All the public land aggregated into one single layer --
---------------------------------------------------------------------
begin;
DROP TABLE IF EXISTS outputs.public_land_merged CASCADE;

CREATE TABLE outputs.public_land_merged AS
SELECT
  row_number() OVER (ORDER BY nm_uf)::numeric AS id,
  nm_uf,
  ST_Multi(geom) AS geom
FROM (
  SELECT nm_uf, geom FROM outputs.public_land_amazonas
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_amapa
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_alagoas
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_acre
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_rio_de_janeiro
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_rio_grande_do_norte
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_rio_grande_do_sul
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_rondonia
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_roraima
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_santa_catarina
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_sao_paulo
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_sergipe
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_tocantins
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_para
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_paraiba
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_pernambuco
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_parana
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_piaui
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_maranhao
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_minas_gerais
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_mato_grosso
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_mato_grosso_do_sul
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_goias
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_espirito_santo
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_distrito_federal
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_bahia
  UNION ALL SELECT nm_uf, geom FROM outputs.public_land_ceara
) s;

-- Primary key on id
ALTER TABLE outputs.public_land_merged
  ADD CONSTRAINT public_land_merged_pk PRIMARY KEY (id);

-- Spatial index
CREATE INDEX public_land_merged_geom_gix
  ON outputs.public_land_merged
  USING GIST (geom);

ANALYZE outputs.public_land_merged;
end;


ANALYZE outputs.public_land_merged;
end;


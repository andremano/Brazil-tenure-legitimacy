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




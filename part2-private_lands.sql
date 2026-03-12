-- Queries developed by Andre da Silva Mano | a.dasilvamano[at]utwente.nl | 2025

-----------------------------------------------------------------------------
-- BLOCK 8 : Private land fully compliant (LEVEL 2): SIGEF and CAR overlap --
-----------------------------------------------------------------------------


	/*
	Create table sigef_car. This table represents a fully copmpliant private property where a CAR polygon overlaps with the respective SIGEF polygon in at least 99 % of the area.
	The initial version of this query was generated with the help of ChatGPT 5.1 on the 8th of December of 2025 from the following prompt: "I have a polygon table named sigef_20251010 and another named car_20251010. 
	For everypolygon in the car table where the centroid intersects a polygon in the sigef table, I want to know if the respectivee polygons overlap for atleast 99% of the area". The query generated
	by ChatGPT was then expanded and reviewed by the authors. 
	*/

		begin; 

			CREATE TABLE outputs.sigef_car AS
			SELECT
				row_number() over()                AS id,
				c.cod_imovel        AS car_id,
				s.parcela_co        AS sigef_id,
				s.art               AS art,
				inter_area / car_area   AS overlap_ratio_sigef,
				sigef_area / car_area   AS size_ratio_sigef_car,
				2                   AS compliance_level,
				s.geom
			FROM raw_data.car_20251010 c
			JOIN raw_data.sigef_20250918 s
			  ON ST_Contains(s.geom, ST_PointOnSurface(c.geom))
			CROSS JOIN LATERAL (
				SELECT
					ST_Area(c.geom)                          AS car_area,
					ST_Area(s.geom)                          AS sigef_area,
					ST_Area(ST_Intersection(st_makevalid(c.geom), st_makevalid(s.geom))) AS inter_area
			) AS x
			WHERE inter_area / car_area >= 0.99      -- = 99% of CAR covered by SIGEF
			  AND sigef_area <= car_area * 1.01;     -- SIGEF = 1% larger than CAR


			-- Add PK
			ALTER TABLE outputs.sigef_car
			ADD CONSTRAINT sigef_car_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.sigef_car'::regclass);

			-- Create spatial index

			CREATE INDEX idx_sigef_Car_geom ON outputs.sigef_Car USING GIST ( geom );
			CREATE INDEX ON outputs.sigef_car(sigef_id);

		end;


--------------------------------------------------------------------------------------------
-- BLOCK 9 : Private land fully compliant (LEVEL 1): SIGEF and CAR overlap + SNCI overlap --
--------------------------------------------------------------------------------------------


	/*
	From the table outputs.sigef_car, a second compliance test verifies, if there is also overlap with the old SNCI System.
	*/

		begin; 

			CREATE TABLE outputs.sigef_car_snci AS
			SELECT
				row_number() over()                AS id,
				sc.car_id,        
				sc.sigef_id,       
				sc.art,
				snci.num_certif,
				inter_area / sigef_car_area   AS overlap_ratio_sigef,
				snci_area / sigef_car_area   AS size_ratio_sigef_car,
				1                   AS compliance_level,
				sc.geom
			FROM outputs.sigef_car sc
			JOIN raw_data.snci_20250918 snci
			  ON ST_Contains(snci.geom, ST_PointOnSurface(sc.geom))
			CROSS JOIN LATERAL (
				SELECT
					ST_Area(sc.geom)                          AS sigef_car_area,
					ST_Area(snci.geom)                          AS snci_area,
					ST_Area(ST_Intersection(st_makevalid(sc.geom), st_makevalid(snci.geom))) AS inter_area
			) AS x
			WHERE inter_area / sigef_car_area >= 0.99      -- = 99% of sigef_car covered by SNCI
			  AND snci_area <= sigef_car_area * 1.01;     -- SNCI = 1% larger than sigef_car;


			-- Add PK
			ALTER TABLE outputs.sigef_car_snci
			ADD CONSTRAINT sigef_car_snci_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.sigef_car_snci'::regclass);

			-- Create spatial index
			CREATE INDEX idx_sigef_car_snci_geom ON outputs.sigef_car_snci USING GIST ( geom );

		end;
		
		
------------------------------------------------------------------------------
-- BLOCK 10 : Create a table with SIGEF parcels that do not overlap with CAR --
------------------------------------------------------------------------------


	-- SIGEF parcels that do not overlap with CAR will be saved in a table named sigef_no_overlap_car. This table will then be used in subsquent steps

		begin;
		
			CREATE TABLE outputs.sigef_no_overlap_car AS
			SELECT *
			FROM raw_data.sigef_20250918 AS s
			WHERE NOT EXISTS (
				SELECT 1
				FROM outputs.sigef_car AS sc
				WHERE sc.sigef_id = s.parcela_co
			);


			-- Add PK
			ALTER TABLE outputs.sigef_no_overlap_car
			ADD CONSTRAINT sigef_no_overlap_car_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.sigef_no_overlap_car'::regclass);

			-- Create spatial index

			CREATE INDEX idx_sigef_no_overlap_car_geom ON outputs.sigef_no_overlap_car USING GIST ( geom );
						
			CREATE INDEX ON raw_data.sigef_20250918(parcela_co);

		end;
	

-------------------------------------------------------------------------------------------------------------------------
-- BLOCK 11 : Remove from the previous set, the sigef parcels that are  overlaping with outputs.sigef_car_snci table --
-------------------------------------------------------------------------------------------------------------------------


		begin;
		
			DELETE FROM outputs.sigef_no_overlap_car AS c
			USING outputs.sigef_car_snci AS s
			WHERE ST_Intersects(c.geom, ST_PointOnSurface(s.geom));
			
		end;
		
		
-------------------------------------------------------------------------------
-- BLOCK 12 : Create a table with CAR parcels that do not overlap with SIGEF --
-------------------------------------------------------------------------------


	-- CAR parcels that do not overlap with CAR will be saved in a table named car_no_overlap_sigef. This table will then be used in subsquent steps
	
		begin;

			CREATE INDEX ON raw_data.car_20251010(cod_imovel);

			CREATE TABLE outputs.car_no_overlap_sigef AS
			SELECT *
			FROM raw_data.car_20251010 AS c
			WHERE NOT EXISTS (
				SELECT 1
				FROM outputs.sigef_car AS sc
				WHERE sc.car_id = c.cod_imovel
			);

			-- Add PK
			ALTER TABLE outputs.car_no_overlap_sigef
			ADD CONSTRAINT car_no_overlap_sigef_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.car_no_overlap_sigef'::regclass);

			-- Create spatial index

			CREATE INDEX idx_car_no_overlap_sigef_geom ON outputs.car_no_overlap_sigef USING GIST ( geom );
			
		end;
		

-------------------------------------------------------------------------------------------------
-- BLOCK 13 : SIGEF parcels overlapping SNCI parcels that DO NOT overlap CAR parcels (LEVEL 3) --
-------------------------------------------------------------------------------------------------


	-- The SIGEF Parcels Not overlapping CAR or CAR + SNCI, will be tested for overlapping with SNCI only			

		begin; 

			CREATE TABLE outputs.sigef_snci AS
			SELECT
				row_number() over()                AS id,
				snoc.parcela_co        AS sigef_id,
				snoc.art               AS art,
				snci.num_certif,
				inter_area / sigef_area   AS overlap_ratio_sigef,
				sigef_area / snci_area   AS size_ratio_sigef_car,
				3                   AS compliance_level,
				snoc.geom
			FROM outputs.sigef_no_overlap_car as snoc
			JOIN raw_data.snci_20250918 snci
			  ON ST_Contains(snoc.geom, ST_PointOnSurface(snci.geom))
			CROSS JOIN LATERAL (
				SELECT
					ST_Area(snci.geom)                          AS snci_area,
					ST_Area(snoc.geom)                          AS sigef_area,
					ST_Area(ST_Intersection(st_makevalid(snci.geom), st_makevalid(snoc.geom))) AS inter_area
			) AS x
			WHERE inter_area / sigef_area >= 0.99	-- = 99% of SIGEF covered by SNCI
			AND sigef_area <= snci_area * 1.01;		-- SNCI area = 1% larger than SIGEF


			-- Create PK
			ALTER TABLE outputs.sigef_snci 
			ADD CONSTRAINT sigef_snci_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.sigef_snci'::regclass);

			-- Create spatial index
			CREATE INDEX idx_sigef_snci_geom ON outputs.sigef_snci USING GIST ( geom );

		end;
		
		
-----------------------------------------------------------------------------
-- BLOCK 14 : SIGEF parcels that do not overlap with CAR or SNCI (LEVEL 4) --
-----------------------------------------------------------------------------	


		/* 
	The initial version of this query was generated with the help of ChatGPT 5.1 on the 15th of December of 2025 from the following prompt:
	"I have a tables called raw.sigef_20250918 outputs.sigef_car, outputs.sigef_car_snci and outputs.sigef_snci. 
	I want to create a new table called outputs.sigef_only where the attribute 'parcela_co' of the first table does 
	not occur in any of the other tables undet the attribute 'sigef_id' (an attribute that occurs in the three other tables.
	This is for Postgres"
	*/
		
		begin;
							
			CREATE INDEX ON raw_data.sigef_20250918 (parcela_co);
			CREATE INDEX ON outputs.sigef_car (sigef_id);
			CREATE INDEX ON outputs.sigef_car_snci (sigef_id);
			CREATE INDEX ON outputs.sigef_snci (sigef_id);
			
			CREATE TABLE outputs.sigef_only AS
			SELECT r.*,
			       4 AS compliance_level
			FROM raw_data.sigef_20250918 r
			WHERE NOT EXISTS (
			    SELECT 1
			    FROM outputs.sigef_car c
			    WHERE c.sigef_id = r.parcela_co
			)
			AND NOT EXISTS (
			    SELECT 1
			    FROM outputs.sigef_car_snci cs
			    WHERE cs.sigef_id = r.parcela_co
			)
			AND NOT EXISTS (
			    SELECT 1
			    FROM outputs.sigef_snci s
			    WHERE s.sigef_id = r.parcela_co
			);

			-- Add PK
			ALTER TABLE outputs.sigef_only
			ADD CONSTRAINT sigef_only_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.sigef_only'::regclass);

			-- Create spatial index
			CREATE INDEX idx_sigef_only_geom ON outputs.sigef_only USING GIST ( geom );
			CREATE INDEX ON outputs.sigef_only(id);
		
		end;
		

--------------------------------------------------------
-- BLOCK 15 : CAR parcels overlap with SNCI (LEVEL 4) --
--------------------------------------------------------	


/*
		
		begin;
		
					
			CREATE INDEX ON raw_data.sigef_20250918 (parcela_co);
			CREATE INDEX ON outputs.sigef_car (sigef_id);
			CREATE INDEX ON outputs.sigef_car_snci (sigef_id);
			CREATE INDEX ON outputs.sigef_snci (sigef_id);
			
			CREATE TABLE outputs.sigef_only AS
			SELECT r.*,
			       4 AS compliance_level
			FROM raw_data.sigef_20250918 r
			WHERE NOT EXISTS (
			    SELECT 1
			    FROM outputs.sigef_car c
			    WHERE c.sigef_id = r.parcela_co
			)
			AND NOT EXISTS (
			    SELECT 1
			    FROM outputs.sigef_car_snci cs
			    WHERE cs.sigef_id = r.parcela_co
			)
			AND NOT EXISTS (
			    SELECT 1
			    FROM outputs.sigef_snci s
			    WHERE s.sigef_id = r.parcela_co
			);

			-- Add PK
			ALTER TABLE outputs.sigef_only
			ADD CONSTRAINT sigef_only_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.sigef_only'::regclass);

			-- Create spatial index
			CREATE INDEX idx_sigef_only_geom ON outputs.sigef_only USING GIST ( geom );
			CREATE INDEX ON outputs.sigef_only(id);
		
		end;
		
	*/
----------------------------------------------------------------------------------------
-- BLOCK 16 : SNCI parcels that do not overlap SIGEF+CAR or do not overlap SIGEF only --
----------------------------------------------------------------------------------------


	/*
	SIGEF parcels that do not overlap with CAR will be saved in a table named sigef_no_overlap_car. This table will then be used in subsquent steps.
	The initial version of this query was generated with the help of ChatGPT 5.1 on the 15th of December of 2025 from the following prompt: 
	"I have a table called raw_data.snci_20250918, outputs.sigef_snci, outputs.sigef_car_snci aI want to create a new table called outputs.snci_no_overlap_car_or_sigef 
	where I select the rows of the first table whenever the centroid of its gemoetries do not intersect with at least one of the polygons of the other two tables"
	*/
	
		begin;
		
			CREATE TABLE outputs.snci_no_overlap_sigef AS
			SELECT s.*
			FROM raw_data.snci_20250918 s
			WHERE NOT EXISTS (
				SELECT 1
				FROM outputs.sigef_snci a
				WHERE ST_Intersects(
					ST_PointOnSurface(s.geom),
					a.geom
				)
			)
			AND NOT EXISTS (
				SELECT 1
				FROM outputs.sigef_car_snci b
				WHERE ST_Intersects(
					ST_PointOnSurface(s.geom),
					b.geom
				)
			);
			
			
			-- Add PK
			ALTER TABLE outputs.snci_no_overlap_sigef
			ADD CONSTRAINT snci_no_overlap_sigef_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.snci_no_overlap_sigef'::regclass);

			-- Create spatial index
			CREATE INDEX idx_snci_no_overlap_sigef_geom ON outputs.snci_no_overlap_sigef USING GIST ( geom );
			CREATE INDEX ON outputs.snci_no_overlap_sigef(id);
			
			
		end;
		
		
--------------------------------------------------------
-- BLOCK 17 : SNCI parcels that overlap CAR (LEVEL 5) --
--------------------------------------------------------


		begin; 

			CREATE TABLE outputs.snci_car AS
			SELECT
				row_number() over()                AS id,
				c.cod_imovel AS car_id,
				s.num_proces,
				s.num_certif,
				s.data_certi,
				inter_area / car_area   AS overlap_ratio_snci,
				snci_area / car_area   AS size_ratio_snci_car,
				5                   AS compliance_level,
				s.geom
			FROM outputs.snci_no_overlap_sigef s
			JOIN outputs.car_no_overlap_sigef c
			  ON ST_Contains(s.geom, ST_PointOnSurface(c.geom))
			CROSS JOIN LATERAL (
				SELECT
					ST_Area(c.geom)                          AS car_area,
					ST_Area(s.geom)                          AS snci_area,
					ST_Area(ST_Intersection(st_makevalid(c.geom), st_makevalid(s.geom))) AS inter_area
			) AS x
			WHERE inter_area / car_area >= 0.99      -- = 99% of CAR covered by SNCI
			  AND snci_area <= car_area * 1.01;     -- SNCI = 1% larger than CAR

			-- Add PK
			ALTER TABLE outputs.snci_car
			ADD CONSTRAINT snci_car_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.snci_car'::regclass);

			-- Create spatial index
			CREATE INDEX idx_snci_car_geom ON outputs.snci_car USING GIST ( geom );
			CREATE INDEX ON outputs.snci_car(id);

		end;
		

-------------------------------------------------------------------------------
-- BLOCK 18 : SNCI parcels that do not overlap with CAR (or SIGEF) (LEVEL 6) --
-------------------------------------------------------------------------------


		begin;
		
			CREATE TABLE outputs.snci_only AS
			SELECT s.*,
			6 AS compliance_level
			FROM raw_data.snci_20250918 s
			WHERE NOT EXISTS (
				SELECT 1
				FROM outputs.sigef_snci a
				WHERE ST_Intersects(
					ST_PointOnSurface(s.geom),
					a.geom
				)
			)
			AND NOT EXISTS (
				SELECT 1
				FROM outputs.snci_car b
				WHERE ST_Intersects(
					ST_PointOnSurface(s.geom),
					b.geom
				)
			);
			
			-- Add PK
			ALTER TABLE outputs.snci_only
			ADD CONSTRAINT snci_only_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.snci_only'::regclass);

			-- Create spatial index
			CREATE INDEX idx_snci_only_geom ON outputs.snci_only USING GIST ( geom );
			CREATE INDEX ON outputs.snci_only(id);
			
		end;
		

------------------------------------------------------------------------------
-- BLOCK 19 : CAR parcels that do not overlap with SIGEF or SNCI (LEVEL 7) --
------------------------------------------------------------------------------


		begin;

			CREATE TABLE outputs.car_only AS
			SELECT a.*,
			7 AS compliance_level
			FROM outputs.car_no_overlap_sigef a
			WHERE NOT EXISTS (
				SELECT 1
				FROM outputs.snci_car b
				WHERE b.car_id = a.cod_imovel
			);
						
		
			-- Add PK
			ALTER TABLE outputs.car_only
			ADD CONSTRAINT car_only_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.car_only'::regclass);

			-- Create spatial index
			CREATE INDEX idx_car_only_geom ON outputs.car_only USING GIST ( geom );
			CREATE INDEX ON outputs.car_only(id);
			
	
		end;
		
------------------------------------------------------------------------------------------------------
-- BLOCK 20 : Remove from table sigef_car, the (sigef) parcels that also occur under sigef_car_snig --
------------------------------------------------------------------------------------------------------


DELETE FROM outputs.sigef_car c
WHERE EXISTS (
  SELECT 1
  FROM outputs.sigef_car_snci s
  WHERE ST_Intersects(
    ST_PointOnSurface(c.geom),
    s.geom
  )
);


---------------------------------------------------------------------
-- BLOCK 21 : Overall compliance table ignonring boundary overlaps --
---------------------------------------------------------------------


	/* This is a table compiling the 7 tables (one for each compliance level) IGRNORING boundary overlaps. 
	The initial version of this query was generated with the help of ChatGPT 5.1 on the 15th of December of 2025 from the following prompt: 
	"I have 7 polygon tables I want to merge into one. In front of each table I have the fields I want to include:
	
	outputs.sigef_car_snci car_id as car_cod_imovel     
						   sigef_id as sigef_parcela_co
						   num_certif as snci_num_certif
						   geom
						   
	outputs.sigef_car      car_id as car_cod_imovel      
						   sigef_id as sigef_parcela_co
						   geom
						   
	outputs.sigef_snci	   car_id as car_cod_imovel      
						   sigef_id as sigef_parcela_co
						   num_certif
						   geom
						   
	outputs.sigef_only	   parcela_co as sigef_parcela_co
						   geom
						   
	outputs.snci_car	   car_id as car_cod_imovel
						   num_certif as_snci_num_certif
						   geom
						   
	outputs.snci_only	   num_certif as snci_num_certif
						   geom
						   
	outputs.car_only       cod_imovel as car_cod_imovel
						   geom
	*/
	
	begin;

			CREATE TABLE outputs.compliance_table_with_overlaps AS
			SELECT
			  car_id    AS car_cod_imovel,
			  sigef_id  AS sigef_parcela_co,
			  num_certif AS snci_num_certif,
			  compliance_level,
			  geom
			FROM outputs.sigef_car_snci

			UNION ALL
			SELECT
			  car_id    AS car_cod_imovel,
			  sigef_id  AS sigef_parcela_co,
			  NULL::text AS snci_num_certif,
			  compliance_level,
			  geom
			FROM outputs.sigef_car

			UNION ALL
			SELECT
			  NULL::text    AS car_cod_imovel,
			  sigef_id  AS sigef_parcela_co,
			  num_certif AS snci_num_certif,
			  compliance_level,
			  geom
			FROM outputs.sigef_snci

			UNION ALL
			SELECT
			  NULL::text AS car_cod_imovel,
			  parcela_co AS sigef_parcela_co,
			  NULL::text AS snci_num_certif,
			  compliance_level,
			  geom
			FROM outputs.sigef_only

			UNION ALL
			SELECT
			  car_id    AS car_cod_imovel,
			  NULL::text AS sigef_parcela_co,
			  num_certif AS snci_num_certif,
			  compliance_level,
			  geom
			FROM outputs.snci_car

			UNION ALL
			SELECT
			  NULL::text AS car_cod_imovel,
			  NULL::text AS sigef_parcela_co,
			  num_certif AS snci_num_certif,
			  compliance_level,
			  geom
			FROM outputs.snci_only

			UNION ALL
			SELECT
			  cod_imovel AS car_cod_imovel,
			  NULL::text AS sigef_parcela_co,
			  NULL::text AS snci_num_certif,
			  compliance_level,
			  geom
			FROM outputs.car_only
			;
			
			-- Add id field
			ALTER TABLE outputs.compliance_table_with_overlaps
			ADD COLUMN id BIGSERIAL;

			-- Add PK 
			ALTER TABLE outputs.compliance_table_with_overlaps
			ADD CONSTRAINT compliance_table_with_overlaps_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.compliance_table_with_overlaps'::regclass);

			-- Create spatial index
			CREATE INDEX idx_compliance_table_with_overlaps_geom ON outputs.compliance_table_with_overlaps USING GIST ( geom );
			CREATE INDEX ON outputs.compliance_table_with_overlaps(id);
	end;
	
	
	
---------------------------------------------------------------------------------------------------------
-- ADDENDUM Split the car_only by state for using in subsequent operations and/or state level analysis --
---------------------------------------------------------------------------------------------------------

/* The query below will generate 27 tables (one per state) containing all the cars in that state. It was generated
from the following ChatGPT 5.2 prompt:

I have a table named outputs.car_only co and another called raw_data.brasil_estados be. 
Under the nm_uf attribute of be there is the name of 27 states: Acre Alagoas Amapá Amazonas Bahia 
Ceará Distrito Federal Espírito Santo Goiás Maranhão Mato Grosso Mato Grosso do Sul Minas Gerais 
Pará Paraíba Paraná Pernambuco Piauí Rio de Janeiro Rio Grande do Norte Rio Grande do Sul Rondônia 
Roraima Santa Catarina São Paulo Sergipe Tocantins I want to create one table for each state from 
the clipping of co with be (so 27 states). Each table shall have all the attributes of car_only 
with the id as PK and spatial indexes on geom. Make sure the spatial functions like intersections 
care for possible geometry errors (st_makevalid, buffer 0 etc). All the tables shall be created 
under the schemma outputs following this naming convention: car_only_name_of_the_state */

DO $$
DECLARE
  r RECORD;
  suffix TEXT;
  tbl TEXT;
BEGIN
  FOR r IN
    SELECT nm_uf, geom
    FROM raw_data.brasil_estados
  LOOP
    -- Map nm_uf (with accents/spaces) to safe snake_case suffix (no accents)
    suffix := CASE r.nm_uf
      WHEN 'Acre' THEN 'acre'
      WHEN 'Alagoas' THEN 'alagoas'
      WHEN 'Amapá' THEN 'amapa'
      WHEN 'Amazonas' THEN 'amazonas'
      WHEN 'Bahia' THEN 'bahia'
      WHEN 'Ceará' THEN 'ceara'
      WHEN 'Distrito Federal' THEN 'distrito_federal'
      WHEN 'Espírito Santo' THEN 'espirito_santo'
      WHEN 'Goiás' THEN 'goias'
      WHEN 'Maranhão' THEN 'maranhao'
      WHEN 'Mato Grosso' THEN 'mato_grosso'
      WHEN 'Mato Grosso do Sul' THEN 'mato_grosso_do_sul'
      WHEN 'Minas Gerais' THEN 'minas_gerais'
      WHEN 'Pará' THEN 'para'
      WHEN 'Paraíba' THEN 'paraiba'
      WHEN 'Paraná' THEN 'parana'
      WHEN 'Pernambuco' THEN 'pernambuco'
      WHEN 'Piauí' THEN 'piaui'
      WHEN 'Rio de Janeiro' THEN 'rio_de_janeiro'
      WHEN 'Rio Grande do Norte' THEN 'rio_grande_do_norte'
      WHEN 'Rio Grande do Sul' THEN 'rio_grande_do_sul'
      WHEN 'Rondônia' THEN 'rondonia'
      WHEN 'Roraima' THEN 'roraima'
      WHEN 'Santa Catarina' THEN 'santa_catarina'
      WHEN 'São Paulo' THEN 'sao_paulo'
      WHEN 'Sergipe' THEN 'sergipe'
      WHEN 'Tocantins' THEN 'tocantins'
      ELSE NULL
    END;

    IF suffix IS NULL THEN
      RAISE NOTICE 'Skipping unknown state name: %', r.nm_uf;
      CONTINUE;
    END IF;

    tbl := 'car_only_' || suffix;

    -- Drop/recreate the state table
    EXECUTE format('DROP TABLE IF EXISTS outputs.%I;', tbl);

    -- Create table with all co columns + a clipped/fixed geom_fix
    -- Then filter to keep only non-empty results
    EXECUTE format($sql$
      CREATE TABLE outputs.%I AS
      SELECT *
      FROM (
        SELECT
          co.*,
          -- Robust clipped geom (polygonal only), fixed against topology errors
          ST_Multi(
            ST_CollectionExtract(
              ST_Buffer(
                ST_MakeValid(
                  ST_Intersection(
                    ST_Buffer(ST_MakeValid(co.geom), 0),
                    ST_Buffer(ST_MakeValid($1), 0)
                  )
                ),
                0
              ),
              3
            )
          ) AS geom_fix
        FROM outputs.car_only co
        WHERE
          co.geom IS NOT NULL
          AND NOT ST_IsEmpty(co.geom)
          AND ST_Intersects(
            ST_Buffer(ST_MakeValid(co.geom), 0),
            ST_Buffer(ST_MakeValid($1), 0)
          )
      ) s
      WHERE
        s.geom_fix IS NOT NULL
        AND NOT ST_IsEmpty(s.geom_fix);
    $sql$, tbl)
    USING r.geom;

    -- Replace original geom with geom_fix (no need to list all columns)
    EXECUTE format('ALTER TABLE outputs.%I DROP COLUMN geom;', tbl);
    EXECUTE format('ALTER TABLE outputs.%I RENAME COLUMN geom_fix TO geom;', tbl);

    -- Primary key + spatial index
    EXECUTE format('ALTER TABLE outputs.%I ADD CONSTRAINT %I PRIMARY KEY (id);', tbl, tbl || '_pkey');
    EXECUTE format('CREATE INDEX %I ON outputs.%I USING GIST (geom);', tbl || '_geom_gix', tbl);

    -- Stats
    EXECUTE format('ANALYZE outputs.%I;', tbl);

    RAISE NOTICE 'Created outputs.% with clipped geometries.', tbl;
  END LOOP;
END $$;

-- Queries developed by Andre da Silva Mano | a.dasilvamano[at]utwente.nl | 2025

-----------------------------------
-- BLOCK 22 : traditional claims --
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
-- BLOCK 23 : aggregated into one single layer --
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



--===================================
-- BLOCK 27: Car over public land) --
--===================================

/* The table  car_over_public_land represents private claims that are most likely unregularizable due to being a claim over 
already registered public land

The query was revised and adapted by the author based on a first query generated by ChatGPT 5.2 based on the following prompt:

From the table outputs.car_only, create a new table named outputs.car_over_public_land.
The new table should contain all attributes of outputs.car_only, but only for those polygons whose 
area overlaps by at least 1% with any polygon in the table outputs_public_merged.
The 1% threshold should be calculated relative to the total area of each polygon in outputs.car_only. */

begin;

SET client_encoding TO 'LATIN1';

-- Acre
DROP TABLE IF EXISTS outputs.car_over_public_land_acre;
CREATE TABLE outputs.car_over_public_land_acre AS
SELECT c.*
FROM outputs.car_nm_uf_acre c
CROSS JOIN outputs.public_land_acre p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_acre ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_acre_geom_idx
  ON outputs.car_over_public_land_acre
  USING GIST (geom);

-- Alagoas
DROP TABLE IF EXISTS outputs.car_over_public_land_alagoas;
CREATE TABLE outputs.car_over_public_land_alagoas AS
SELECT c.*
FROM outputs.car_nm_uf_alagoas c
CROSS JOIN outputs.public_land_alagoas p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_alagoas ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_alagoas_geom_idx
  ON outputs.car_over_public_land_alagoas
  USING GIST (geom);

-- Amapa
DROP TABLE IF EXISTS outputs.car_over_public_land_amapa;
CREATE TABLE outputs.car_over_public_land_amapa AS
SELECT c.*
FROM outputs.car_nm_uf_amapa c
CROSS JOIN outputs.public_land_amapa p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_amapa ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_amapa_geom_idx
  ON outputs.car_over_public_land_amapa
  USING GIST (geom);

-- Amazonas
DROP TABLE IF EXISTS outputs.car_over_public_land_amazonas;
CREATE TABLE outputs.car_over_public_land_amazonas AS
SELECT c.*
FROM outputs.car_nm_uf_amazonas c
CROSS JOIN outputs.public_land_amazonas p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_amazonas ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_amazonas_geom_idx
  ON outputs.car_over_public_land_amazonas
  USING GIST (geom);

-- Bahia
DROP TABLE IF EXISTS outputs.car_over_public_land_bahia;
CREATE TABLE outputs.car_over_public_land_bahia AS
SELECT c.*
FROM outputs.car_nm_uf_bahia c
CROSS JOIN outputs.public_land_bahia p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_bahia ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_bahia_geom_idx
  ON outputs.car_over_public_land_bahia
  USING GIST (geom);

-- Ceara
DROP TABLE IF EXISTS outputs.car_over_public_land_ceara;
CREATE TABLE outputs.car_over_public_land_ceara AS
SELECT c.*
FROM outputs.car_nm_uf_ceara c
CROSS JOIN outputs.public_land_ceara p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_ceara ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_ceara_geom_idx
  ON outputs.car_over_public_land_ceara
  USING GIST (geom);

-- Distrito Federal
DROP TABLE IF EXISTS outputs.car_over_public_land_distrito_federal;
CREATE TABLE outputs.car_over_public_land_distrito_federal AS
SELECT c.*
FROM outputs.car_nm_uf_distrito_federal c
CROSS JOIN outputs.public_land_distrito_federal p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_distrito_federal ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_distrito_federal_geom_idx
  ON outputs.car_over_public_land_distrito_federal
  USING GIST (geom);

-- Espirito Santo
DROP TABLE IF EXISTS outputs.car_over_public_land_espirito_santo;
CREATE TABLE outputs.car_over_public_land_espirito_santo AS
SELECT c.*
FROM outputs.car_nm_uf_espirito_santo c
CROSS JOIN outputs.public_land_espirito_santo p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_espirito_santo ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_espirito_santo_geom_idx
  ON outputs.car_over_public_land_espirito_santo
  USING GIST (geom);

-- Goias
DROP TABLE IF EXISTS outputs.car_over_public_land_goias;
CREATE TABLE outputs.car_over_public_land_goias AS
SELECT c.*
FROM outputs.car_nm_uf_goias c
CROSS JOIN outputs.public_land_goias p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_goias ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_goias_geom_idx
  ON outputs.car_over_public_land_goias
  USING GIST (geom);

-- Maranhao
DROP TABLE IF EXISTS outputs.car_over_public_land_maranhao;
CREATE TABLE outputs.car_over_public_land_maranhao AS
SELECT c.*
FROM outputs.car_nm_uf_maranhao c
CROSS JOIN outputs.public_land_maranhao p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_maranhao ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_maranhao_geom_idx
  ON outputs.car_over_public_land_maranhao
  USING GIST (geom);

-- Mato Grosso
DROP TABLE IF EXISTS outputs.car_over_public_land_mato_grosso;
CREATE TABLE outputs.car_over_public_land_mato_grosso AS
SELECT c.*
FROM outputs.car_nm_uf_mato_grosso c
CROSS JOIN outputs.public_land_mato_grosso p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_mato_grosso ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_mato_grosso_geom_idx
  ON outputs.car_over_public_land_mato_grosso
  USING GIST (geom);

-- Mato Grosso do Sul
DROP TABLE IF EXISTS outputs.car_over_public_land_mato_grosso_do_sul;
CREATE TABLE outputs.car_over_public_land_mato_grosso_do_sul AS
SELECT c.*
FROM outputs.car_nm_uf_mato_grosso_do_sul c
CROSS JOIN outputs.public_land_mato_grosso_do_sul p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_mato_grosso_do_sul ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_mato_grosso_do_sul_geom_idx
  ON outputs.car_over_public_land_mato_grosso_do_sul
  USING GIST (geom);

-- Minas Gerais
DROP TABLE IF EXISTS outputs.car_over_public_land_minas_gerais;
CREATE TABLE outputs.car_over_public_land_minas_gerais AS
SELECT c.*
FROM outputs.car_nm_uf_minas_gerais c
CROSS JOIN outputs.public_land_minas_gerais p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_minas_gerais ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_minas_gerais_geom_idx
  ON outputs.car_over_public_land_minas_gerais
  USING GIST (geom);

-- Para
DROP TABLE IF EXISTS outputs.car_over_public_land_para;
CREATE TABLE outputs.car_over_public_land_para AS
SELECT c.*
FROM outputs.car_nm_uf_para c
CROSS JOIN outputs.public_land_para p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_para ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_para_geom_idx
  ON outputs.car_over_public_land_para
  USING GIST (geom);

-- Paraiba
DROP TABLE IF EXISTS outputs.car_over_public_land_paraiba;
CREATE TABLE outputs.car_over_public_land_paraiba AS
SELECT c.*
FROM outputs.car_nm_uf_paraiba c
CROSS JOIN outputs.public_land_paraiba p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_paraiba ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_paraiba_geom_idx
  ON outputs.car_over_public_land_paraiba
  USING GIST (geom);

-- Parana
DROP TABLE IF EXISTS outputs.car_over_public_land_parana;
CREATE TABLE outputs.car_over_public_land_parana AS
SELECT c.*
FROM outputs.car_nm_uf_parana c
CROSS JOIN outputs.public_land_parana p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_parana ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_parana_geom_idx
  ON outputs.car_over_public_land_parana
  USING GIST (geom);

-- Pernambuco
DROP TABLE IF EXISTS outputs.car_over_public_land_pernambuco;
CREATE TABLE outputs.car_over_public_land_pernambuco AS
SELECT c.*
FROM outputs.car_nm_uf_pernambuco c
CROSS JOIN outputs.public_land_pernambuco p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_pernambuco ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_pernambuco_geom_idx
  ON outputs.car_over_public_land_pernambuco
  USING GIST (geom);

-- Piaui
DROP TABLE IF EXISTS outputs.car_over_public_land_piaui;
CREATE TABLE outputs.car_over_public_land_piaui AS
SELECT c.*
FROM outputs.car_nm_uf_piaui c
CROSS JOIN outputs.public_land_piaui p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_piaui ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_piaui_geom_idx
  ON outputs.car_over_public_land_piaui
  USING GIST (geom);

-- Rio de Janeiro
DROP TABLE IF EXISTS outputs.car_over_public_land_rio_de_janeiro;
CREATE TABLE outputs.car_over_public_land_rio_de_janeiro AS
SELECT c.*
FROM outputs.car_nm_uf_rio_de_janeiro c
CROSS JOIN outputs.public_land_rio_de_janeiro p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_rio_de_janeiro ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_rio_de_janeiro_geom_idx
  ON outputs.car_over_public_land_rio_de_janeiro
  USING GIST (geom);

-- Rio Grande do Norte
DROP TABLE IF EXISTS outputs.car_over_public_land_rio_grande_do_norte;
CREATE TABLE outputs.car_over_public_land_rio_grande_do_norte AS
SELECT c.*
FROM outputs.car_nm_uf_rio_grande_do_norte c
CROSS JOIN outputs.public_land_rio_grande_do_norte p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_rio_grande_do_norte ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_rio_grande_do_norte_geom_idx
  ON outputs.car_over_public_land_rio_grande_do_norte
  USING GIST (geom);

-- Rio Grande do Sul
DROP TABLE IF EXISTS outputs.car_over_public_land_rio_grande_do_sul;
CREATE TABLE outputs.car_over_public_land_rio_grande_do_sul AS
SELECT c.*
FROM outputs.car_nm_uf_rio_grande_do_sul c
CROSS JOIN outputs.public_land_rio_grande_do_sul p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_rio_grande_do_sul ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_rio_grande_do_sul_geom_idx
  ON outputs.car_over_public_land_rio_grande_do_sul
  USING GIST (geom);

-- Rondonia
DROP TABLE IF EXISTS outputs.car_over_public_land_rondonia;
CREATE TABLE outputs.car_over_public_land_rondonia AS
SELECT c.*
FROM outputs.car_nm_uf_rondonia c
CROSS JOIN outputs.public_land_rondonia p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_rondonia ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_rondonia_geom_idx
  ON outputs.car_over_public_land_rondonia
  USING GIST (geom);

-- Roraima
DROP TABLE IF EXISTS outputs.car_over_public_land_roraima;
CREATE TABLE outputs.car_over_public_land_roraima AS
SELECT c.*
FROM outputs.car_nm_uf_roraima c
CROSS JOIN outputs.public_land_roraima p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_roraima ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_roraima_geom_idx
  ON outputs.car_over_public_land_roraima
  USING GIST (geom);

-- Santa Catarina
DROP TABLE IF EXISTS outputs.car_over_public_land_santa_catarina;
CREATE TABLE outputs.car_over_public_land_santa_catarina AS
SELECT c.*
FROM outputs.car_nm_uf_santa_catarina c
CROSS JOIN outputs.public_land_santa_catarina p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_santa_catarina ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_santa_catarina_geom_idx
  ON outputs.car_over_public_land_santa_catarina
  USING GIST (geom);

-- Sao Paulo
DROP TABLE IF EXISTS outputs.car_over_public_land_sao_paulo;
CREATE TABLE outputs.car_over_public_land_sao_paulo AS
SELECT c.*
FROM outputs.car_nm_uf_sao_paulo c
CROSS JOIN outputs.public_land_sao_paulo p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_sao_paulo ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_sao_paulo_geom_idx
  ON outputs.car_over_public_land_sao_paulo
  USING GIST (geom);

-- Sergipe
DROP TABLE IF EXISTS outputs.car_over_public_land_sergipe;
CREATE TABLE outputs.car_over_public_land_sergipe AS
SELECT c.*
FROM outputs.car_nm_uf_sergipe c
CROSS JOIN outputs.public_land_sergipe p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_sergipe ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_sergipe_geom_idx
  ON outputs.car_over_public_land_sergipe
  USING GIST (geom);

-- Tocantins
DROP TABLE IF EXISTS outputs.car_over_public_land_tocantins;
CREATE TABLE outputs.car_over_public_land_tocantins AS
SELECT c.*
FROM outputs.car_nm_uf_tocantins c
CROSS JOIN outputs.public_land_tocantins p
WHERE ST_Intersects(c.geom, p.geom)
  AND ST_Area(ST_Intersection(c.geom, p.geom)) / NULLIF(ST_Area(c.geom), 0) > 0.01;
ALTER TABLE outputs.car_over_public_land_tocantins ADD PRIMARY KEY (id);
CREATE INDEX car_over_public_land_tocantins_geom_idx
  ON outputs.car_over_public_land_tocantins
  USING GIST (geom);

end;


--=========================================
-- BLOCK 28: Car over public land merged --
--=========================================


DROP TABLE IF EXISTS outputs.car_over_public_land_merged;

CREATE TABLE outputs.car_over_public_land_merged AS
WITH unioned AS (

    SELECT
        'acre' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_acre

    UNION ALL
    SELECT
        'alagoas' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_alagoas

    UNION ALL
    SELECT
        'amapa' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_amapa

    UNION ALL
    SELECT
        'amazonas' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_amazonas

    UNION ALL
    SELECT
        'bahia' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_bahia

    UNION ALL
    SELECT
        'ceara' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_ceara

    UNION ALL
    SELECT
        'distrito_federal' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_distrito_federal

    UNION ALL
    SELECT
        'espirito_santo' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_espirito_santo

    UNION ALL
    SELECT
        'goias' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_goias

    UNION ALL
    SELECT
        'maranhao' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_maranhao

    UNION ALL
    SELECT
        'mato_grosso' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_mato_grosso

    UNION ALL
    SELECT
        'mato_grosso_do_sul' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_mato_grosso_do_sul

    UNION ALL
    SELECT
        'minas_gerais' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_minas_gerais

    UNION ALL
    SELECT
        'para' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_para

    UNION ALL
    SELECT
        'paraiba' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_paraiba

    UNION ALL
    SELECT
        'parana' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_parana

    UNION ALL
    SELECT
        'pernambuco' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_pernambuco

    UNION ALL
    SELECT
        'piaui' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_piaui

    UNION ALL
    SELECT
        'rio_de_janeiro' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_rio_de_janeiro

    UNION ALL
    SELECT
        'rio_grande_do_norte' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_rio_grande_do_norte

    UNION ALL
    SELECT
        'rio_grande_do_sul' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_rio_grande_do_sul

    UNION ALL
    SELECT
        'rondonia' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_rondonia

    UNION ALL
    SELECT
        'roraima' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_roraima

    UNION ALL
    SELECT
        'santa_catarina' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_santa_catarina

    UNION ALL
    SELECT
        'sao_paulo' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_sao_paulo

    UNION ALL
    SELECT
        'sergipe' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_sergipe

    UNION ALL
    SELECT
        'tocantins' AS state,
        geom,
        id,
        cod_imovel,
        status_imo,
        dat_criaca,
        data_atual,
        area,
        condicao,
        uf,
        municipio,
        cod_munici
    FROM outputs.car_over_public_land_tocantins
)

SELECT
    ROW_NUMBER() OVER () AS fid,
    state,
    geom,
    id,
    cod_imovel,
    status_imo,
    dat_criaca,
    data_atual,
    area,
    condicao,
    uf,
    municipio,
    cod_munici
FROM unioned;

ALTER TABLE outputs.car_over_public_land_merged
    ADD CONSTRAINT car_over_public_land_merged_pkey PRIMARY KEY (fid);

CREATE INDEX car_over_public_land_merged_geom_gix
    ON outputs.car_over_public_land_merged
    USING GIST (geom);


--======================================
-- BLOCK 29: Car only (final version) --
--======================================


/* the final version of the car only table represents a Private land claim based on a car that does not overlap any other existing claims
The query was revised and adapted by the author based on a first query generated by ChatGPT 5.2 based on the following prompt:

I have a table called outputs.car_only. then I have a table called outputs.traditional_claims, another called outputs.private_claims and
 yet another called outputs.car_over_public_land. The four tables have  an attribute called cod_imovel. I want to remove from outputs.car_only 
 the records whose cod_imovel occur in any of the other 3 tables. */
 
 DELETE FROM outputs.car_only c
WHERE EXISTS (
    SELECT 1
    FROM outputs.traditional_claims t
    WHERE t.cod_imovel = c.cod_imovel
)
OR EXISTS (
    SELECT 1
    FROM outputs.private_claims_merged p
    WHERE p.cod_imovel = c.cod_imovel
)
OR EXISTS (
    SELECT 1
    FROM outputs.private_claims_regularizable l
    WHERE l.cod_imovel = c.cod_imovel
)
OR EXISTS (
    SELECT 1
    FROM outputs.car_over_public_land_merged l
    WHERE l.cod_imovel = c.cod_imovel
);
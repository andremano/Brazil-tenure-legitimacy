-- Queries developed by Andre da Silva Mano | a.dasilvamano[at]utwente.nl | 2025

-----------------------------------------------------------------------------
-- BLOCK 6 : Private land fully compliant (LEVEL 2): SIGEF and CAR overlap --
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
-- BLOCK 7 : Private land fully compliant (LEVEL 1): SIGEF and CAR overlap + SNCI overlap --
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
-- BLOCK 8 : Create a table with SIGEF parcels that do not overlap with CAR --
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
-- BLOCK 9 : Remove from the previous set, the sigef parcels that are  overlaping with outputs.sigef_car_snci table --
-------------------------------------------------------------------------------------------------------------------------


		begin;
		
			DELETE FROM outputs.sigef_no_overlap_car AS c
			USING outputs.sigef_car_snci AS s
			WHERE ST_Intersects(c.geom, ST_PointOnSurface(s.geom));
			
		end;
		
		
-------------------------------------------------------------------------------
-- BLOCK 10 : Create a table with CAR parcels that do not overlap with SIGEF --
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
-- BLOCK 11 : SIGEF parcels overlapping SNCI parcels that DO NOT overlap CAR parcels (LEVEL 3) --
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
-- BLOCK 12 : SIGEF parcels that do not overlap with CAR or SNCI (LEVEL 4) --
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
-- BLOCK 13 : CAR parcels overlap with SNCI (LEVEL 4) --
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
-- BLOCK 14 : SNCI parcels that do not overlap SIGEF+CAR or do not overlap SIGEF only --
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
-- BLOCK 15 : SNCI parcels that overlap CAR (LEVEL 5) --
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
-- BLOCK 16 : SNCI parcels that do not overlap with CAR (or SIGEF) (LEVEL 6) --
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
-- BLOCK 17 : CAR parcels that do not overlap with SIGEF or SNCI (LEVEL 7) --
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
-- BLOCK 18 : Remove from table sigef_car, the (sigef) parcels that also occur under sigef_car_snig --
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
-- BLOCK 18 : Overall compliance table ignonring boundary overlaps --
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
	
	
------------------------------------
-- BLOCK 19 : Summary of overlaps --
------------------------------------


	/* This is a table compiling the 7 tables (one for each compliance level) EXCLUDING boundary overlaps



---------------------------------------------------------------------
-- BLOCK 20 : Overall compliance table excluding boundary overlaps --
---------------------------------------------------------------------


	/* This is a table compiling the 7 tables (one for each compliance level) EXCLUDING boundary overlaps

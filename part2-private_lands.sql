-- Queries by Andre da Silva Mano | a.dasilvamano[at]utwente.nl

-----------------------------------------------------------------------------
-- BLOCK 6 : Private land fully compliant (LEVEL 1): SIGEF and CAR overlap --
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
				1                   AS compliance_level,
				c.geom
			FROM raw_data.car_20251010 c
			JOIN raw_data.sigef_20250918 s
			  ON ST_Contains(s.geom, ST_Centroid(c.geom))
			CROSS JOIN LATERAL (
				SELECT
					ST_Area(c.geom)                          AS car_area,
					ST_Area(s.geom)                          AS sigef_area,
					ST_Area(ST_Intersection(st_makevalid(c.geom), st_makevalid(s.geom))) AS inter_area
			) AS x
			WHERE inter_area / car_area >= 0.99      -- = 99% of CAR covered by SIGEF
			  AND sigef_area <= car_area * 1.01;     -- SIGEF = 1% larger than CAR



			ALTER TABLE outputs.sigef_car
			ADD CONSTRAINT sigef_car_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.sigef_car'::regclass);

			-- Create spatial index

			CREATE INDEX idx_sigef_Car_geom ON outputs.sigef_Car USING GIST ( geom );

		end;


----------------------------------------------------------
-- BLOCK 7 : SIGEF parcels that do not overlap with CAR --
----------------------------------------------------------


	-- SIGEF parcels that do not overlap with CAR will be saved in a table named sigef_no_overlap_car. This table will then be used in subsquent steps

		begin;
		
			CREATE INDEX ON outputs.sigef_car(sigef_id);
			CREATE INDEX ON raw_data.sigef_20250918(parcela_co);

			CREATE TABLE outputs.sigef_no_overlap_car AS
			SELECT *
			FROM raw_data.sigef_20250918 AS s
			WHERE NOT EXISTS (
				SELECT 1
				FROM outputs.sigef_car AS sc
				WHERE sc.sigef_id = s.parcela_co
			);


			-- Add Primary Key
			ALTER TABLE outputs.sigef_no_overlap_car
			ADD CONSTRAINT sigef_no_overlap_car_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.sigef_no_overlap_car'::regclass);

			-- Create spatial index

			CREATE INDEX idx_sigef_no_overlap_car_geom ON outputs.sigef_no_overlap_car USING GIST ( geom );

		end;
		
		
----------------------------------------------------------
-- BLOCK 8 : CAR parcels that do not overlap with SIGEG --
----------------------------------------------------------


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

			-- Add Primary Key
			ALTER TABLE outputs.car_no_overlap_sigef
			ADD CONSTRAINT car_no_overlap_sigef_pkey PRIMARY KEY (id);

			-- Register geometry columns
			SELECT Populate_Geometry_Columns('outputs.car_no_overlap_sigef'::regclass);

			-- Create spatial index

			CREATE INDEX idx_car_no_overlap_sigef_geom ON outputs.car_no_overlap_sigef USING GIST ( geom );
			
		end;
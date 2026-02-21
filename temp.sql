/*I have a table named outputs.car_only co and another called raw_data.brasil_estados be. 
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


/*I have:

A table outputs.public_land_merged (plm) containing 27 records, one polygon per Brazilian state.
27 tables named outputs.car_only_<state_name>, each corresponding to a single state and created previously by clipping outputs.car_only.
Now I want to generate 27 new tables, one for each state, using the corresponding car_only_<state> table and the matching state polygon in public_land_merged.
For each state:
Use the respective outputs.car_only_<state> table as co.
Use the matching state polygon from outputs.public_land_merged as plm.
Select only the features from co where tipo_imove is either 'AST' or 'PCT'.
Keep only those features whose area of overlap with the corresponding state polygon in plm is less than or equal to 1% of the feature's own area.
The resulting table must:
Be created under schema outputs
Follow a consistent naming convention (e.g., traditional_claims_<state>)
Contain all attributes from the respective co table
Contain no attributes from plm
Include an additional column compliance_level INTEGER, initially NULL
Have a primary key constraint on id
Have a GiST spatial index on geom
All spatial operations must be robust to geometry errors (e.g., use ST_MakeValid, ST_Buffer(…,0) where necessary). */

DO $$
DECLARE
  r RECORD;
  suffix TEXT;
  state_name TEXT;
  out_tbl TEXT;
  plm_geom geometry;
BEGIN
  FOR r IN
    SELECT tablename
    FROM pg_catalog.pg_tables
    WHERE schemaname = 'outputs'
      AND tablename LIKE 'car_only\_%' ESCAPE '\'
    ORDER BY tablename
  LOOP
    suffix := substring(r.tablename from '^car_only_(.*)$');

    state_name := CASE suffix
      WHEN 'acre' THEN 'Acre'
      WHEN 'alagoas' THEN 'Alagoas'
      WHEN 'amapa' THEN 'Amapá'
      WHEN 'amazonas' THEN 'Amazonas'
      WHEN 'bahia' THEN 'Bahia'
      WHEN 'ceara' THEN 'Ceará'
      WHEN 'distrito_federal' THEN 'Distrito Federal'
      WHEN 'espirito_santo' THEN 'Espírito Santo'
      WHEN 'goias' THEN 'Goiás'
      WHEN 'maranhao' THEN 'Maranhão'
      WHEN 'mato_grosso' THEN 'Mato Grosso'
      WHEN 'mato_grosso_do_sul' THEN 'Mato Grosso do Sul'
      WHEN 'minas_gerais' THEN 'Minas Gerais'
      WHEN 'para' THEN 'Pará'
      WHEN 'paraiba' THEN 'Paraíba'
      WHEN 'parana' THEN 'Paraná'
      WHEN 'pernambuco' THEN 'Pernambuco'
      WHEN 'piaui' THEN 'Piauí'
      WHEN 'rio_de_janeiro' THEN 'Rio de Janeiro'
      WHEN 'rio_grande_do_norte' THEN 'Rio Grande do Norte'
      WHEN 'rio_grande_do_sul' THEN 'Rio Grande do Sul'
      WHEN 'rondonia' THEN 'Rondônia'
      WHEN 'roraima' THEN 'Roraima'
      WHEN 'santa_catarina' THEN 'Santa Catarina'
      WHEN 'sao_paulo' THEN 'São Paulo'
      WHEN 'sergipe' THEN 'Sergipe'
      WHEN 'tocantins' THEN 'Tocantins'
      ELSE NULL
    END;

    IF state_name IS NULL THEN
      RAISE NOTICE 'Skipping table % (could not map suffix: %)', r.tablename, suffix;
      CONTINUE;
    END IF;

    -- Assumes outputs.public_land_merged has nm_uf + geom
    SELECT geom
    INTO plm_geom
    FROM outputs.public_land_merged
    WHERE nm_uf = state_name
    LIMIT 1;

    IF plm_geom IS NULL THEN
      RAISE NOTICE 'Skipping state % (no matching plm record found)', state_name;
      CONTINUE;
    END IF;

    out_tbl := 'traditional_claims_' || suffix;

    EXECUTE format('DROP TABLE IF EXISTS outputs.%I;', out_tbl);

    EXECUTE format($sql$
      CREATE TABLE outputs.%I AS
      WITH plm_fix AS (
        SELECT ST_Buffer(ST_MakeValid($1), 0) AS plm_geom_fix
      )
      SELECT
        s.*
      FROM (
        SELECT
          co.*,
          ST_Multi(
            ST_CollectionExtract(
              ST_Buffer(ST_MakeValid(co.geom), 0),
              3
            )
          ) AS geom_fix
        FROM outputs.%I co
        WHERE
          co.tipo_imove IN ('AST', 'PCT')
          AND co.geom IS NOT NULL
          AND NOT ST_IsEmpty(co.geom)
      ) s
      CROSS JOIN plm_fix p
      WHERE
        s.geom_fix IS NOT NULL
        AND NOT ST_IsEmpty(s.geom_fix)
        AND ST_Area(s.geom_fix) > 0
        AND (
          COALESCE(
            ST_Area(
              ST_CollectionExtract(
                ST_Intersection(s.geom_fix, p.plm_geom_fix),
                3
              )
            ),
            0
          ) <= 0.01 * ST_Area(s.geom_fix)
        );
    $sql$, out_tbl, r.tablename)
    USING plm_geom;

    -- Drop original geom, rename geom_fix -> geom (so output geom is the fixed one)
    EXECUTE format('ALTER TABLE outputs.%I DROP COLUMN geom;', out_tbl);
    EXECUTE format('ALTER TABLE outputs.%I RENAME COLUMN geom_fix TO geom;', out_tbl);

    -- compliance_level empty (NULL)
    EXECUTE format('ALTER TABLE outputs.%I ADD COLUMN IF NOT EXISTS compliance_level integer;', out_tbl);
    EXECUTE format('UPDATE outputs.%I SET compliance_level = NULL;', out_tbl);

    -- PK + spatial index
    EXECUTE format('ALTER TABLE outputs.%I ADD CONSTRAINT %I PRIMARY KEY (id);', out_tbl, out_tbl || '_pkey');
    EXECUTE format('CREATE INDEX %I ON outputs.%I USING GIST (geom);', out_tbl || '_geom_gix', out_tbl);

    EXECUTE format('ANALYZE outputs.%I;', out_tbl);

    RAISE NOTICE 'Created outputs.% for state % (source: outputs.%)', out_tbl, state_name, r.tablename;
  END LOOP;
END $$;
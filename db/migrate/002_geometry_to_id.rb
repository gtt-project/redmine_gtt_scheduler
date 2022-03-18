class GeometryToId < ActiveRecord::Migration[5.2]
  def up
    execute <<-SQL
      CREATE OR REPLACE FUNCTION geom_to_id(geom GEOMETRY)
      RETURNS BIGINT
      AS $$
      DECLARE
        lat_prefix CHAR(1) := '0';
        lon_prefix CHAR(1) := '0';
        latitude FLOAT;
        longitude FLOAT;
      BEGIN
        IF ST_GeometryType(geom) != 'ST_Point' THEN
          RAISE EXCEPTION 'The input geometry must be a point';
        END IF;

        latitude := ST_Y(geom);
        longitude := ST_X(geom);

        IF latitude < 0 THEN
          lat_prefix := '1';
        END IF;
        IF longitude < 0 THEN
          lon_prefix := '1';
        END IF;
        RETURN
          CONCAT(
            lat_prefix,
            LPAD(ROUND(10000 * ABS(latitude))::TEXT, 7, '0'),
            lon_prefix,
            LPAD(ROUND(10000 * ABS(longitude))::TEXT, 7, '0')
          )::BIGINT;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE STRICT;
    SQL
  end

  def down
    execute <<-SQL
      DROP FUNCTION IF EXISTS geom_to_id(geom GEOMETRY);
    SQL
  end
end

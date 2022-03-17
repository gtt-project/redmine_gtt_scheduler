class CoordinatesToId < ActiveRecord::Migration[5.2]
  def up
    execute <<-SQL
      CREATE OR REPLACE FUNCTION coord_to_id(latitude FLOAT, longitude FLOAT)
      RETURNS BIGINT
      AS $$
      DECLARE
        lat_prefix CHAR(1) := '0';
        lon_prefix CHAR(1) := '0';
      BEGIN
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
      DROP FUNCTION IF EXISTS coord_to_id(latitude FLOAT, longitude FLOAT);
    SQL
  end
end

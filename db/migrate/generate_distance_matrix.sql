-- postgresql function that takes id, latitude and longitude as input and generates start_id, end_id and distance matrix
CREATE OR REPLACE FUNCTION generate_distance_matrix(integer, double precision, double precision)
RETURNS TABLE (start_id integer, end_id integer, distance integer) AS
$$
DECLARE
  start_id integer;
  end_id integer;
  distance integer;
BEGIN
  FOR start_id IN SELECT id FROM gtt_scheduler_stops WHERE latitude = $2 AND longitude = $3 LOOP
    FOR end_id IN SELECT id FROM gtt_scheduler_stops WHERE latitude != $2 AND longitude != $3 LOOP
      distance = (6371 * acos(cos(radians($2)) * cos(radians(latitude)) * cos(radians(longitude) - radians($3)) + sin(radians($2)) * sin(radians(latitude))));
      RETURN NEXT;
    END LOOP;
  END LOOP;
  RETURN;
END;

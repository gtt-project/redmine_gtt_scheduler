module RedmineGttScheduler
  module Scheduler
    # Reduces an issue's geometry to the single [lon, lat] the solver and the map
    # both work with. Shared so the problem and the map cannot disagree about
    # where an issue is.
    module Geometry
      # Returns [lon, lat], or nil only when there is genuinely nothing to use.
      #
      # `centroid` is not available for every geometry type on the geographic
      # factory Redmine uses (it needs a GEOS-backed factory), and it notably
      # fails for LineString. Since a road segment is a LineString, relying on
      # centroid alone silently dropped exactly the geometries this plugin most
      # needs, so fall back to a vertex-derived representative point.
      def self.point_of(geom)
        return nil if geom.nil?

        point_coords(geom) || centroid_coords(geom) || vertex_coords(geom)
      end

      def self.point_coords(geom)
        return nil unless geom.geometry_type == RGeo::Feature::Point

        [geom.x, geom.y]
      rescue StandardError
        nil
      end

      def self.centroid_coords(geom)
        centroid = geom.respond_to?(:centroid) ? geom.centroid : nil
        return nil if centroid.nil? || centroid.is_empty?

        [centroid.x, centroid.y]
      rescue StandardError
        nil
      end

      # Midpoint vertex of the geometry's coordinate list: stable, cheap, and
      # always on the feature itself, which matters for a long road segment
      # where an averaged point could fall off the road entirely.
      def self.vertex_coords(geom)
        points = vertices(geom)
        return nil if points.empty?

        middle = points[points.size / 2]
        [middle.x, middle.y]
      rescue StandardError
        nil
      end

      def self.vertices(geom)
        if geom.respond_to?(:points)
          geom.points
        elsif geom.respond_to?(:exterior_ring)
          geom.exterior_ring.points
        elsif geom.respond_to?(:geometry_n) && geom.respond_to?(:num_geometries) && geom.num_geometries.positive?
          vertices(geom.geometry_n(0))
        else
          []
        end
      rescue StandardError
        []
      end

      private_class_method :point_coords, :centroid_coords, :vertex_coords, :vertices
    end
  end
end

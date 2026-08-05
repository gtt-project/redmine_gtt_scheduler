module RedmineGttScheduler
  module Scheduler
    # Builds the GeoJSON a run's map renders: one point per stop plus one line
    # per resource joining its stops in visit order.
    #
    # A route follows the real road path when the solver returned geometry for
    # it (VROOM's `g` option), and falls back to straight legs between
    # consecutive stops when it did not, so an older run or a solver asked
    # without geometry still renders.
    class RouteGeoJson
      # Used for the per-resource swatch and timeline bars. It is also emitted as
      # a feature property, but redmine_gtt's map renderer currently styles every
      # feature the same way and ignores it; the property is kept so the map can
      # follow suit once per-feature styling is available.
      COLORS = %w[#1f77b4 #d62728 #2ca02c #ff7f0e #9467bd #8c564b #e377c2 #7f7f7f].freeze

      def self.color_for(index)
        COLORS[index % COLORS.size]
      end

      # geometries: resource id => encoded polyline from the solver. When one is
      # present and decodes plausibly, the route follows the actual roads;
      # otherwise it falls back to straight legs between consecutive stops.
      def self.call(assignments, geometries: {})
        new(assignments, geometries: geometries).call
      end

      def initialize(assignments, geometries: {})
        @assignments = assignments
        @geometries = geometries || {}
      end

      def call
        by_resource = @assignments.group_by(&:scheduler_resource_id)
        order = by_resource.keys.compact.sort
        features = []
        order.each_with_index do |resource_id, index|
          stops = by_resource[resource_id].sort_by(&:sequence)
          color = self.class.color_for(index)
          points = []
          stops.each do |assignment|
            point = Geometry.point_of(assignment.issue&.geom)
            next if point.nil?

            points << point
            features << stop_feature(assignment, point, color)
          end
          road = road_coordinates(resource_id, points)
          if road
            features << line_feature(stops.first&.scheduler_resource, road, color, road: true)
          elsif points.size > 1
            features << line_feature(stops.first&.scheduler_resource, points, color, road: false)
          end
        end
        {'type' => 'FeatureCollection', 'features' => features}
      end

      private

      def stop_feature(assignment, point, color)
        {
          'type' => 'Feature',
          'geometry' => {'type' => 'Point', 'coordinates' => point},
          'properties' => {
            'id' => assignment.issue_id,
            'subject' => assignment.issue&.subject,
            'sequence' => assignment.sequence,
            # Both the id and the name: the map keys on the id, because resource
            # names are not unique, and shows the name.
            'resource_id' => assignment.scheduler_resource_id,
            'resource' => assignment.scheduler_resource&.name,
            'color' => color
          }
        }
      end

      # Decoded road path for this resource, or nil when there is none to use.
      # The plausibility check is the guard against an upstream precision change:
      # decoding at the wrong precision divides every coordinate by ten, which
      # would quietly draw the route in the wrong hemisphere rather than fail.
      def road_coordinates(resource_id, stops)
        encoded = @geometries[resource_id] || @geometries[resource_id.to_s]
        return nil if encoded.blank?

        decoded = Polyline.decode(encoded)
        return nil unless decoded.size > 1 && Polyline.plausible?(decoded, near: stops)

        decoded
      end

      def line_feature(resource, points, color, road:)
        {
          'type' => 'Feature',
          'geometry' => {'type' => 'LineString', 'coordinates' => points},
          'properties' => {
            'resource' => resource&.name,
            'resource_id' => resource&.id,
            'color' => color,
            # road_path false means the line is only straight legs between
            # stops; the UI states this explicitly instead of presenting the
            # line as a road path.
            'road_path' => road,
            'straight_legs' => !road
          }
        }
      end
    end
  end
end

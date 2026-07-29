module RedmineGttScheduler
  module Scheduler
    # Builds the GeoJSON a run's map renders: one point per stop plus one line
    # per resource joining its stops in visit order.
    #
    # The lines are straight legs between consecutive stops, not the road path.
    # They convey the order and rough shape of a route, which is what a
    # dispatcher reads the map for. Real road geometry needs VROOM's `g` flag
    # and polyline decoding, and is deliberately left for a later change.
    class RouteGeoJson
      # Used for the per-resource swatch and timeline bars. It is also emitted as
      # a feature property, but redmine_gtt's map renderer currently styles every
      # feature the same way and ignores it; the property is kept so the map can
      # follow suit once per-feature styling is available.
      COLORS = %w[#1f77b4 #d62728 #2ca02c #ff7f0e #9467bd #8c564b #e377c2 #7f7f7f].freeze

      def self.color_for(index)
        COLORS[index % COLORS.size]
      end

      def self.call(assignments)
        new(assignments).call
      end

      def initialize(assignments)
        @assignments = assignments
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
          features << leg_feature(stops.first&.scheduler_resource, points, color) if points.size > 1
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
            'resource' => assignment.scheduler_resource&.name,
            'color' => color
          }
        }
      end

      def leg_feature(resource, points, color)
        {
          'type' => 'Feature',
          'geometry' => {'type' => 'LineString', 'coordinates' => points},
          'properties' => {
            'resource' => resource&.name,
            'resource_id' => resource&.id,
            'color' => color,
            'straight_legs' => true
          }
        }
      end
    end
  end
end

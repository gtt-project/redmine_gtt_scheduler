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

      # geometries: resource id => encoded polylines from the solver, each
      # entry a {'date' => iso-date-or-nil, 'geometry' => encoded} hash
      # (see SchedulerRun#route_geometries_by_resource; a bare string is
      # accepted for convenience). A multi-day run has one route per
      # resource per day, so the lines are built per day: a day whose
      # geometry is present and decodes plausibly follows the roads, any
      # other day falls back to straight legs between its own stops,
      # never joining stops of different days.
      def self.call(assignments, geometries: {})
        new(assignments, geometries: geometries).call
      end

      def initialize(assignments, geometries: {})
        @assignments = assignments
        @geometries = geometries || {}
        @zone = RedmineGttScheduler.reference_zone
      end

      def call
        by_resource = @assignments.group_by(&:scheduler_resource_id)
        order = by_resource.keys.compact.sort
        features = []
        order.each_with_index do |resource_id, index|
          features.concat(resource_features(resource_id, by_resource[resource_id],
                                            self.class.color_for(index)))
        end
        {'type' => 'FeatureCollection', 'features' => features}
      end

      private

      def resource_features(resource_id, assignments, color)
        resource = assignments.first&.scheduler_resource
        features = []
        assignments.group_by { |a| day_of(a) }.sort_by { |day, _| day.to_s }.each do |day, day_stops|
          points = []
          day_stops.sort_by(&:sequence).each do |assignment|
            point = Geometry.point_of(assignment.issue&.geom)
            next if point.nil?

            points << point
            features << stop_feature(assignment, point, color)
          end

          road = road_coordinates(resource_id, day, points)
          if road
            features << line_feature(resource, road, color, road: true)
          elsif points.size > 1
            features << line_feature(resource, points, color, road: false)
          end
        end
        features
      end

      def day_of(assignment)
        assignment.starts_at&.in_time_zone(@zone)&.to_date
      end

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

      # Decoded road path for this resource on this day, or nil when there
      # is none to use. The plausibility check is the guard against an
      # upstream precision change: decoding at the wrong precision divides
      # every coordinate by ten, which would quietly draw the route in the
      # wrong hemisphere rather than fail.
      def road_coordinates(resource_id, day, stops)
        encoded = encoded_geometry(resource_id, day)
        return nil if encoded.blank?

        decoded = Polyline.decode(encoded)
        return nil unless decoded.size > 1 && Polyline.plausible?(decoded, near: stops)

        decoded
      end

      # The stored entry for this day: matched by ISO date for multi-day
      # runs; a single dateless entry (single-day runs, or a bare string
      # passed directly) applies to whichever day there is.
      def encoded_geometry(resource_id, day)
        raw = @geometries[resource_id] || @geometries[resource_id.to_s]
        entries = (raw.is_a?(Array) ? raw : [raw]).compact.map do |entry|
          entry.is_a?(Hash) ? entry : {'date' => nil, 'geometry' => entry}
        end
        entry = entries.find { |e| e['date'] == day&.iso8601 } ||
                (entries.first if entries.size == 1 && entries.first['date'].nil?)
        entry && entry['geometry']
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

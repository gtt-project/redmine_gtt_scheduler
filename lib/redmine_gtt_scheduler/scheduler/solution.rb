module RedmineGttScheduler
  module Scheduler
    # Backend-independent result of one optimization run.
    class Solution
      Assignment = Struct.new(
        :issue_id, :resource_id, :sequence,
        :starts_at, :ends_at, :travel_seconds,
        keyword_init: true
      )

      attr_reader :assignments, :unassigned_ids, :request, :raw, :route_geometries

      # route_geometries maps a vehicle (resource) id to the encoded polyline
      # VROOM returned for its route, when geometry was requested.
      def initialize(assignments: [], unassigned_ids: [], request: nil, raw: nil,
                     route_geometries: {})
        @assignments = assignments
        @unassigned_ids = unassigned_ids
        @request = request
        @raw = raw
        @route_geometries = route_geometries
      end
    end
  end
end

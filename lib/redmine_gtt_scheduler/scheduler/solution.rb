module RedmineGttScheduler
  module Scheduler
    # Backend-independent result of one optimization run.
    class Solution
      Assignment = Struct.new(
        :issue_id, :resource_id, :sequence,
        :starts_at, :ends_at, :travel_seconds,
        keyword_init: true
      )

      attr_reader :assignments, :unassigned_ids, :request, :raw

      def initialize(assignments: [], unassigned_ids: [], request: nil, raw: nil)
        @assignments = assignments
        @unassigned_ids = unassigned_ids
        @request = request
        @raw = raw
      end
    end
  end
end

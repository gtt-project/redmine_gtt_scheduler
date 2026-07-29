module RedmineGttScheduler
  module Scheduler
    # Backend-independent description of one optimization problem.
    # Locations are [lon, lat]; time windows are [open, close] in epoch
    # seconds; service durations are seconds.
    class Problem
      Job = Struct.new(:id, :location, :service, :time_window, :priority, keyword_init: true)
      Vehicle = Struct.new(:id, :start, :end, :time_window, keyword_init: true)

      attr_reader :jobs, :vehicles, :excluded

      def initialize(jobs: [], vehicles: [], excluded: {})
        @jobs = jobs
        @vehicles = vehicles
        @excluded = excluded
      end

      def solvable?
        jobs.any? && vehicles.any?
      end
    end
  end
end

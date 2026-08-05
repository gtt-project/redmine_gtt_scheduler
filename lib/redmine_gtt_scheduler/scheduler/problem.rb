module RedmineGttScheduler
  module Scheduler
    # Backend-independent description of one optimization problem.
    # Locations are [lon, lat]; time windows are [open, close] in epoch
    # seconds; service durations are seconds. skills are integer ids
    # assigned per problem (see ProblemBuilder#skill_id_map): a job may
    # only be served by a vehicle whose skills cover the job's.
    # delivery/capacity are single-element arrays (one load dimension).
    # Either every job and vehicle carries them or none does: VROOM
    # rejects input where the amount lengths differ (verified against a
    # live solver), which ProblemBuilder guarantees.
    class Problem
      Job = Struct.new(:id, :location, :service, :time_window, :priority, :skills,
                       :delivery, keyword_init: true)
      Vehicle = Struct.new(:id, :start, :end, :time_window, :skills, :capacity,
                           keyword_init: true)

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

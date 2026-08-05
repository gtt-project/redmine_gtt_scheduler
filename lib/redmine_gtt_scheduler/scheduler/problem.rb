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
      # breaks is an array of {id:, time_window:, service:} hashes, one
      # per break the vehicle must take within its day.
      Vehicle = Struct.new(:id, :start, :end, :time_window, :skills, :capacity,
                           :breaks, keyword_init: true)

      # A pickup/delivery pair the same vehicle must serve in order.
      # pickup and delivery are Job structs; amount is the moved load
      # (same single dimension as delivery/capacity), skills and priority
      # apply to the pair as a whole.
      Shipment = Struct.new(:pickup, :delivery, :amount, :skills, :priority,
                            keyword_init: true)

      attr_reader :jobs, :vehicles, :excluded, :vehicle_index, :shipments

      # vehicle_index maps a solver vehicle id to [resource id, Date].
      # Multi-day problems have one vehicle per resource per working day
      # with synthetic ids; single-day problems keep vehicle id ==
      # resource id and an empty index.
      def initialize(jobs: [], vehicles: [], excluded: {}, vehicle_index: {},
                     shipments: [])
        @jobs = jobs
        @vehicles = vehicles
        @excluded = excluded
        @vehicle_index = vehicle_index
        @shipments = shipments
      end

      def resource_id_for(vehicle_id)
        entry = vehicle_index[vehicle_id]
        entry ? entry.first : vehicle_id
      end

      def solvable?
        (jobs.any? || shipments.any?) && vehicles.any?
      end
    end
  end
end

module RedmineGttScheduler
  module Scheduler
    # Runs the full solve for one SchedulerRun: build the problem, call
    # the adapter, persist the proposed assignments. Never raises; the
    # outcome lands in the run's status and error_message.
    class Solver
      def self.call(run, adapter: nil)
        new(run, adapter: adapter).call
      end

      def initialize(run, adapter: nil)
        @run = run
        @adapter = adapter || VroomExpressAdapter.new
      end

      def call
        @run.update!(status: SchedulerRun::SOLVING)
        problem = ProblemBuilder.new(@run).build
        unless problem.solvable?
          fail_run('No plannable issues or no active resources for this day.',
                   excluded: problem.excluded)
          return @run
        end

        solution = @adapter.solve(problem)
        persist(problem, solution)
        @run
      rescue Adapter::SolverError => e
        fail_run(e.message)
        @run
      rescue StandardError => e
        # Anything else escaping the background job would leave the run in
        # "solving" forever, with the UI telling the user to keep reloading.
        # The run must always end in a terminal status.
        Rails.logger.error(
          "[Scheduler] run #{@run.id} crashed: #{e.class}: #{e.message}\n" \
          "#{e.backtrace&.first(10)&.join("\n")}"
        )
        fail_run("#{e.class}: #{e.message}")
        @run
      end

      private

      def persist(problem, solution)
        SchedulerRun.transaction do
          @run.scheduler_assignments.delete_all
          solution.assignments.each do |assignment|
            @run.scheduler_assignments.create!(
              issue_id: assignment.issue_id,
              scheduler_resource_id: assignment.resource_id,
              sequence: assignment.sequence,
              starts_at: assignment.starts_at,
              ends_at: assignment.ends_at,
              travel_seconds: assignment.travel_seconds,
              kind: assignment.kind
            )
          end
          @run.update!(
            status: SchedulerRun::PROPOSED,
            request_payload: JSON.pretty_generate(solution.request),
            response_payload: JSON.pretty_generate(solution.raw),
            excluded_issues: JSON.generate(problem.excluded),
            vehicle_map: vehicle_map_json(problem),
            error_message: nil
          )
        end
      end

      # Multi-day problems use one synthetic vehicle per resource per day;
      # the mapping is stored so readers of the response payload (route
      # geometry) can get back to the resource. nil for single-day runs,
      # whose vehicle ids are the resource ids.
      def vehicle_map_json(problem)
        return nil if problem.vehicle_index.empty?

        JSON.generate(problem.vehicle_index.transform_values do |(resource_id, date)|
          [resource_id, date.iso8601]
        end)
      end

      def fail_run(message, excluded: nil)
        attributes = {
          status: SchedulerRun::FAILED,
          error_message: message.to_s.truncate(2000)
        }
        attributes[:excluded_issues] = JSON.generate(excluded) if excluded
        @run.update!(attributes)
      end
    end
  end
end

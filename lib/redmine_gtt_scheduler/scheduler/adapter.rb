module RedmineGttScheduler
  module Scheduler
    # Base class for solver backends.
    class Adapter
      class SolverError < StandardError; end

      # Takes a Scheduler::Problem, returns a Scheduler::Solution.
      def solve(problem)
        raise NotImplementedError
      end
    end
  end
end

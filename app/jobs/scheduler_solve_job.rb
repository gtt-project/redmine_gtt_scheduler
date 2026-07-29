class SchedulerSolveJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = SchedulerRun.find_by(id: run_id)
    return unless run

    RedmineGttScheduler::Scheduler::Solver.call(run)
  end
end

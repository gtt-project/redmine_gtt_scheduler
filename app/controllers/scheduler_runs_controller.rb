class SchedulerRunsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_run, only: [:show, :apply, :discard]

  def index
    @runs = @project.scheduler_runs.sorted.limit(100)
  end

  def show
    @assignments = @run.scheduler_assignments
                       .includes(:issue, :scheduler_resource)
                       .order(:scheduler_resource_id, :sequence)
    @unassigned_issues = Issue.where(id: @run.unassigned_issue_ids).visible
    @excluded_issues = Issue.where(id: @run.excluded.keys).visible.index_by(&:id)
  end

  def new
    @run = @project.scheduler_runs.build(scheduled_on: User.current.today)
  end

  def create
    @run = @project.scheduler_runs.build(
      user: User.current,
      status: SchedulerRun::DRAFT,
      scheduled_on: params.dig(:scheduler_run, :scheduled_on)
    )
    if @run.save
      SchedulerSolveJob.perform_later(@run.id)
      flash[:notice] = l(:notice_scheduler_run_started)
      redirect_to project_scheduler_run_path(@project, @run)
    else
      render :new
    end
  end

  def apply
    result = RedmineGttScheduler::Scheduler::SolutionApplier.call(@run, User.current)
    if result.success?
      flash[:notice] = l(:notice_scheduler_run_applied)
    else
      flash[:error] = result.message
    end
    redirect_to project_scheduler_run_path(@project, @run)
  end

  def discard
    if @run.discardable?
      @run.update!(status: SchedulerRun::DISCARDED)
      flash[:notice] = l(:notice_scheduler_run_discarded)
    else
      flash[:error] = l(:text_scheduler_not_discardable)
    end
    redirect_to project_scheduler_runs_path(@project)
  end

  private

  def find_run
    @run = @project.scheduler_runs.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end

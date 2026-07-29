class SchedulerRunsController < ApplicationController
  # The run map is drawn with redmine_gtt's own map_tag, so its helper has to be
  # in this controller's helper context. redmine_gtt is a hard dependency of this
  # plugin, so requiring it here costs nothing extra.
  helper :gtt_map

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
    # Grouped and ordered by resource id so a resource's swatch, timeline and
    # table always line up with each other. Note the map does not follow these
    # colours: redmine_gtt's renderer styles all features alike and ignores the
    # per-feature colour in the GeoJSON.
    @assignments_by_resource = @assignments.group_by(&:scheduler_resource)
                                           .sort_by { |resource, _| resource&.id.to_i }
    @route_geojson = RedmineGttScheduler::Scheduler::RouteGeoJson.call(@assignments) if @assignments.any?
    @unassigned_issues = Issue.where(id: @run.unassigned_issue_ids).visible
    @unassigned_reasons = @unassigned_issues.any? ? unassigned_reasons : {}
    @excluded_issues = Issue.where(id: @run.excluded.keys).visible.index_by(&:id)
  end

  def new
    @run = @project.scheduler_runs.build(scheduled_on: User.current.today)
    @resources = @project.scheduler_resources.active.sorted
    @selected_resource_ids = @resources.map(&:id)
  end

  def create
    @run = @project.scheduler_runs.build(
      user: User.current,
      status: SchedulerRun::DRAFT,
      scheduled_on: params.dig(:scheduler_run, :scheduled_on)
    )
    @run.selected_resources = selected_resources
    if @run.save
      SchedulerSolveJob.perform_later(@run.id)
      flash[:notice] = l(:notice_scheduler_run_started)
      redirect_to project_scheduler_run_path(@project, @run)
    else
      @resources = @project.scheduler_resources.active.sorted
      @selected_resource_ids = @run.selected_resources.map(&:id)
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

  # Diagnostics are derived locally (VROOM reports no reason), which means
  # rebuilding the problem. Never let that break the page: a run whose data has
  # since changed should still render its assignments.
  def unassigned_reasons
    RedmineGttScheduler::Scheduler::UnassignedReport.call(@run)
  rescue StandardError => e
    Rails.logger.warn("[Scheduler] unassigned diagnostics failed for run #{@run.id}: #{e.message}")
    {}
  end

  # Only active resources of this project, so a stale or foreign id in the form
  # cannot pull another project's resource into the run. An empty selection is
  # left empty; the run then falls back to all active resources.
  def selected_resources
    ids = Array(params[:scheduler_run_resource_ids]).reject(&:blank?).map(&:to_i)
    return [] if ids.empty?

    @project.scheduler_resources.active.where(id: ids).to_a
  end

  def find_run
    @run = @project.scheduler_runs.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end

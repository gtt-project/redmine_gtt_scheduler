class ScheduleIssuesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  def show
    begin
      (scheduled, unscheduled) = RedmineGttScheduler::ScheduleIssues.(@project)
      flash[:notice] = "Scheduled #{scheduled} issues, #{unscheduled} issues unscheduled."
    rescue => e
      flash[:error] = e.message
    end
    redirect_to :back
  end

  private

  def find_project_by_project_id
    @project = Project.find params[:project_id]
  end

  def authorize
    if User.current.allowed_to?(:manage_members, @project, global: false)
      true
    else
      if @project && @project.archived?
        render_403 :message => :notice_not_authorized_archived_project
      else
        deny_access
      end
    end
  end
end

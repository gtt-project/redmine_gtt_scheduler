class SchedulerResourcesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_resource, only: [:edit, :update, :destroy]

  def index
    @resources = @project.scheduler_resources.sorted
  end

  def new
    @resource = @project.scheduler_resources.build
  end

  def create
    @resource = @project.scheduler_resources.build(resource_params)
    if @resource.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_scheduler_resources_path(@project)
    else
      render :new
    end
  end

  def edit; end

  def update
    if @resource.update(resource_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_scheduler_resources_path(@project)
    else
      render :edit
    end
  end

  def destroy
    @resource.destroy
    if @resource.destroyed?
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = @resource.errors.full_messages.to_sentence.presence ||
                      l(:notice_unable_delete_scheduler_resource)
    end
    redirect_to project_scheduler_resources_path(@project)
  end

  private

  def find_resource
    @resource = @project.scheduler_resources.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def resource_params
    params.require(:scheduler_resource).permit(
      :name, :user_id, :start_lng, :start_lat, :end_lng, :end_lat,
      :work_starts, :work_ends, :active, :capacity,
      :break_starts, :break_ends, :break_minutes,
      skills: [], working_days: []
    )
  end
end

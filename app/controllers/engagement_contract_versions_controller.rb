class EngagementContractVersionsController < ApplicationController
  before_action :find_engagement_contract
  before_action :find_version, only: [:edit, :update, :destroy]
  before_action :authorize

  helper :engagement_contracts

  def new
    @version = @project.versions.build(engagement_contract_id: @engagement_contract.id)
  end

  def create
    @version = @project.versions.build
    @version.engagement_contract = @engagement_contract
    @version.safe_attributes = params[:version]
    if @version.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_engagement_contract_path(@project, @engagement_contract)
    else
      render :new
    end
  end

  def edit
  end

  def update
    @version.safe_attributes = params[:version]
    if @version.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_engagement_contract_path(@project, @engagement_contract)
    else
      render :edit
    end
  end

  def destroy
    @version.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_engagement_contract_path(@project, @engagement_contract)
  end

  private

  def find_engagement_contract
    @engagement_contract = EngagementContract.find(params[:engagement_contract_id])
    @project = @engagement_contract.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_version
    @version = @engagement_contract.versions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize
    if %w[new create].include?(action_name)
      deny_access unless User.current.allowed_to?(:manage_engagement_contract_versions, @project)
    elsif %w[edit update destroy].include?(action_name)
      deny_access unless User.current.allowed_to?(:manage_engagement_contract_versions, @project)
    end
  end
end

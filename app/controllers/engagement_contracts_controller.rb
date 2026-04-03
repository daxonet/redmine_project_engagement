class EngagementContractsController < ApplicationController
  before_action :find_project_by_project_id, only: [:index, :new, :create]
  before_action :find_engagement_contract, only: [:show, :edit, :update, :destroy, :add_version, :remove_version, :reset_dashboard_link]
  before_action :authorize

  helper :engagement_contracts

  def index
    @engagement_contracts = @project.engagement_contracts.order(Arel.sql("CASE WHEN status = 'open' THEN 0 ELSE 1 END, created_on DESC"))
  end

  def show
    @versions = @engagement_contract.sorted_versions
    @available_versions = @project.shared_versions.where(engagement_contract_id: nil).order(:name)
  end

  def new
    @engagement_contract = @project.engagement_contracts.build
  end

  def create
    @engagement_contract = @project.engagement_contracts.build(engagement_contract_params)
    if @engagement_contract.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_engagement_contract_path(@project, @engagement_contract)
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @engagement_contract.update(engagement_contract_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_engagement_contract_path(@project, @engagement_contract)
    else
      render :edit
    end
  end

  def destroy
    @engagement_contract.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_engagement_contracts_list_path(@project)
  end

  def add_version
    version = @project.shared_versions.find(params[:version_id])
    if version.engagement_contract_id.present?
      flash[:error] = l(:error_version_already_assigned, version: version.name)
    else
      version.update(engagement_contract_id: @engagement_contract.id)
      flash[:notice] = l(:notice_version_added, version: version.name)
    end
    redirect_to project_engagement_contract_path(@project, @engagement_contract)
  end

  def remove_version
    version = @engagement_contract.versions.find(params[:version_id])
    version.update(engagement_contract_id: nil)
    flash[:notice] = l(:notice_version_removed, version: version.name)
    redirect_to project_engagement_contract_path(@project, @engagement_contract)
  end

  def reset_dashboard_link
    @engagement_contract.reset_dashboard_secret!
    flash[:notice] = l(:notice_dashboard_link_reset)
    redirect_to project_engagement_contract_path(@project, @engagement_contract)
  end

  private

  def find_engagement_contract
    @engagement_contract = EngagementContract.find(params[:id])
    @project = @engagement_contract.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def engagement_contract_params
    params.require(:engagement_contract).permit(:name, :contract_number, :contract_hours, :contract_date, :description, :status)
  end
end

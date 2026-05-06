class EngagementDashboardController < ApplicationController
  # Public routes: skip login, verify token
  skip_before_action :check_if_login_required, only: [:show, :data, :serve_logo]
  before_action :find_project, only: [:show, :data]
  before_action :find_engagement_contract_by_param, only: [:show, :data]
  before_action :verify_token, only: [:show, :data]

  # Authenticated route: require login + permission
  before_action :find_engagement_contract_by_id, only: [:show_authenticated]
  before_action :authorize, only: [:show_authenticated]

  def show
    @public_mode = true
    @data = build_dashboard_data
    render 'engagement_dashboard/show', layout: false
  end

  def show_authenticated
    @public_mode = false
    @data = build_dashboard_data
    render 'engagement_dashboard/show', layout: false
  end

  def data
    render json: build_dashboard_data
  end

  def upload_logo
    require_admin
    logo_dir = File.join(Rails.root, 'files', 'engagement_plugin')
    FileUtils.mkdir_p(logo_dir)

    if params[:delete] == '1'
      Dir.glob(File.join(logo_dir, 'dashboard_logo.*')).each { |f| File.delete(f) }
      flash[:notice] = 'Logo removed.'
    elsif params[:logo].present?
      Dir.glob(File.join(logo_dir, 'dashboard_logo.*')).each { |f| File.delete(f) }
      uploaded = params[:logo]
      ext = File.extname(uploaded.original_filename).downcase
      dest = File.join(logo_dir, "dashboard_logo#{ext}")
      File.open(dest, 'wb') { |f| f.write(uploaded.read) }
      flash[:notice] = 'Logo uploaded.'
    end

    head :ok
  end

  def serve_logo
    logo_file = Dir.glob(File.join(Rails.root, 'files', 'engagement_plugin', 'dashboard_logo.*')).first
    if logo_file && File.exist?(logo_file)
      send_file logo_file, disposition: 'inline'
    else
      head :not_found
    end
  end

  def self.generate_token(project_identifier, engagement_contract)
    jo = engagement_contract.is_a?(EngagementContract) ? engagement_contract : EngagementContract.find(engagement_contract)
    dashboard_secret = jo.ensure_dashboard_secret
    Digest::SHA256.hexdigest("#{dashboard_secret}:#{project_identifier}:#{jo.id}:dashboard")[0, 20]
  end

  private

  def settings
    @settings ||= Setting.plugin_redmine_project_engagement || {}
  end

  def customization_tracker_id
    settings['customization_tracker_id'].to_i
  end

  def stage_field_id
    settings['stage_field_id']
  end

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    @project = Project.where(identifier: params[:project_id]).first
    render_404 unless @project
  end

  def find_engagement_contract_by_param
    @engagement_contract = EngagementContract.find(params[:engagement_contract_id])
    render_404 unless @engagement_contract && @engagement_contract.project_id == @project.id
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_engagement_contract_by_id
    @engagement_contract = EngagementContract.find(params[:id])
    @project = @engagement_contract.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def verify_token
    expected = self.class.generate_token(@project.identifier, @engagement_contract)
    render_404 unless params[:token] == expected
  end

  def authorize
    deny_access unless User.current.allowed_to?(:view_engagement_dashboard, @project)
  end

  def cf_value(issue, field_id)
    return nil if field_id.blank?
    cv = issue.custom_field_values.detect { |v| v.custom_field_id == field_id.to_i }
    cv&.value
  end

  def version_ids
    @version_ids ||= @engagement_contract.versions.pluck(:id)
  end

  def build_dashboard_data
    all_phases = build_phases

    timeline_phases = all_phases.reject { |p| p[:milestone_type] == 'Additional-Scope' || p[:milestone_type] == 'Project-Management' }

    # Find current: first active phase, promote if next phase progress > current remaining
    current_regular = timeline_phases.detect { |p| p[:status] == 'active' }
    if current_regular
      loop do
        current_idx = timeline_phases.index(current_regular)
        remaining_progress = 100 - current_regular[:progress].to_i
        next_candidate = timeline_phases[(current_idx + 1)..].detect { |p| p[:status] == 'active' }
        if next_candidate && next_candidate[:progress].to_i > remaining_progress
          current_regular = next_candidate
        else
          break
        end
      end
    end
    current_idx = current_regular ? timeline_phases.index(current_regular) : nil
    next_phase = current_idx ? timeline_phases[(current_idx + 1)..].detect { |p| p[:status] != 'done' } : timeline_phases.detect { |p| p[:status] == 'upcoming' }

    cr_milestone = all_phases.select { |p| p[:milestone_type] == 'Customization' }.detect { |p|
      Issue.open.where(fixed_version_id: p[:version_id], tracker_id: customization_tracker_id).exists?
    }

    # Previous milestone: the phase right before current (only if not 100%)
    prev_phase = current_idx && current_idx > 0 ? timeline_phases[current_idx - 1] : nil
    prev_phase = nil if prev_phase && prev_phase[:progress].to_i >= 100

    # Build milestone detail cards
    milestone_cards = []
    if prev_phase
      milestone_cards << { phase: prev_phase, label: 'PREVIOUS', tasks: [] }
    end
    if current_regular
      if current_regular[:milestone_type] == 'Customization'
        milestone_cards << { phase: current_regular, label: 'CURRENT', tasks: build_customization_task_list(current_regular[:version_id]) }
      else
        milestone_cards << { phase: current_regular, label: 'CURRENT', tasks: build_milestone_tasks(current_regular[:version_id], :open) }
      end
    end
    if next_phase
      milestone_cards << { phase: next_phase, label: 'NEXT', tasks: [] }
    end

    {
      project:          { name: @project.name, identifier: @project.identifier,
                          subject: @engagement_contract.name },
      kpis:             build_kpis(all_phases),
      phases:           timeline_phases,
      milestone_cards:  milestone_cards,
      milestones:       all_phases.reject { |p| p[:milestone_type] == 'Project-Management' },
      customization_status: build_cr_pipeline,
      tracker_breakdown: build_tracker_breakdown,
      team_hours:       build_team_hours,
      active_crs:       build_active_crs,
      updated_at:       Time.now.strftime('%Y-%m-%d %H:%M:%S')
    }
  end

  def build_kpis(phases)
    base = Issue.where(fixed_version_id: version_ids)
    open_issues = base.open
    today = Date.today

    go_live_phase = phases.detect { |p| p[:milestone_type] == 'Go-Live' }
    go_live_date = go_live_phase ? go_live_phase[:start_date] : nil
    go_live_days = go_live_date ? (Date.parse(go_live_date) - today).to_i : nil

    waiting_status_ids = IssueStatus.where("name LIKE '%Customer%'").pluck(:id)
    closed_status_ids = IssueStatus.where(is_closed: true).pluck(:id)

    main_phases = phases.reject { |p| p[:milestone_type] == 'Additional-Scope' || p[:milestone_type] == 'Project-Management' }
    phase_count = main_phases.length
    overall_progress = phase_count > 0 ? (main_phases.sum { |p| p[:progress].to_i }.to_f / phase_count).round : 0

    {
      go_live_days:    go_live_days,
      total_open:      open_issues.count,
      overdue:         open_issues.where('due_date < ?', today).count,
      waiting:         open_issues.where(status_id: waiting_status_ids).count,
      resolved:        base.where(status_id: closed_status_ids).where('closed_on >= ?', 30.days.ago).count,
      overall_progress: overall_progress
    }
  end

  def build_phases
    today = Date.today
    @engagement_contract.sorted_versions.map do |v|
      issues = v.fixed_issues
      progress = issues.count > 0 ? issues.completed_percent.round : 0

      status = if progress >= 100
                 'done'
               elsif progress > 0 || (v.planned_start_date && v.planned_start_date <= today)
                 'active'
               elsif v.planned_start_date && v.planned_start_date > today
                 'upcoming'
               else
                 'upcoming'
               end

      {
        version_id:     v.id,
        id:             v.id,
        subject:        v.name,
        status:         status,
        progress:       progress,
        start_date:     v.planned_start_date&.to_s,
        due_date:       v.effective_date&.to_s,
        baseline_start: v.planned_start_date&.to_s,
        baseline_due:   v.effective_date&.to_s,
        issue_status:   v.status,
        milestone_type: v.version_sub_type
      }
    end
  end

  # Tasks for previous/current/next milestone cards
  # Shows assigned open tasks (including subtasks) grouped under parent
  def build_milestone_tasks(version_id, mode)
    scope = Issue.where(fixed_version_id: version_id)
                 .where.not(tracker_id: customization_tracker_id)
                 .includes(:assigned_to, :status)

    if mode == :open
      scope = scope.open
    elsif mode == :started
      scope = scope.where("start_date <= ? OR done_ratio > 0", Date.today)
    end

    # Get top-level tasks
    top_tasks = scope.where(parent_id: nil).order(:start_date)
    # Get assigned subtasks (tasks with parent that have an assignee)
    assigned_subtasks = scope.where.not(parent_id: nil).where.not(assigned_to_id: nil).order(:start_date)

    items = []
    top_tasks.each do |t|
      subs = assigned_subtasks.select { |s| s.parent_id == t.id }
      if subs.any?
        # Show subtasks instead of parent
        subs.each do |s|
          items << {
            id:       s.id,
            subject:  s.subject.truncate(50),
            progress: s.done_ratio || 0,
            assignee: s.assigned_to&.firstname || '-',
            status:   s.status&.name
          }
        end
      else
        items << {
          id:       t.id,
          subject:  t.subject.truncate(50),
          progress: t.done_ratio || 0,
          assignee: t.assigned_to&.firstname || '-',
          status:   t.status&.name
        }
      end
    end

    # Also include assigned subtasks whose parent is not in this version
    orphan_subs = assigned_subtasks.reject { |s| top_tasks.any? { |t| t.id == s.parent_id } }
    orphan_subs.each do |s|
      items << {
        id:       s.id,
        subject:  s.subject.truncate(50),
        progress: s.done_ratio || 0,
        assignee: s.assigned_to&.firstname || '-',
        status:   s.status&.name
      }
    end

    items.first(12)
  end

  # Customization milestone: summary per configured stage (done/total %)
  def build_customization_task_list(version_id)
    return [] if stage_field_id.blank?

    configured_stages = settings_stage_list

    # Get ALL subtasks of customization issues in this version, grouped by stage
    cr_ids = Issue.where(fixed_version_id: version_id, tracker_id: customization_tracker_id).pluck(:id)
    return [] if cr_ids.empty?

    subtask_tid = settings['customization_subtask_tracker_id'].to_i
    subtasks = Issue.where(parent_id: cr_ids, tracker_id: subtask_tid)
                    .includes(:status, :custom_values)

    configured_stages.map do |stage|
      stage_subs = subtasks.select { |s| s.subject.downcase.include?("[#{stage.downcase}]") }
      total = stage_subs.size
      done = stage_subs.count { |s| s.status&.is_closed? || s.done_ratio == 100 }
      pct = total > 0 ? (done.to_f / total * 100).round : 0

      {
        id:       nil,
        subject:  "Customization #{stage}",
        progress: pct,
        assignee: "#{done}/#{total}",
        status:   stage
      }
    end
  end

  def settings_stage_list
    val = settings['stage_subtask_list']
    if val.is_a?(Array)
      val.reject(&:blank?)
    else
      (val || '').split(',').map(&:strip).reject(&:blank?)
    end
  end

  def build_phase_children(phase)
    if phase[:milestone_type] == 'Customization'
      build_customization_children(phase[:version_id])
    else
      build_task_children(phase[:version_id])
    end
  end

  def build_task_children(version_id)
    children = Issue.where(fixed_version_id: version_id)
                    .where.not(tracker_id: customization_tracker_id)
                    .open
                    .where(parent_id: nil)
                    .includes(:assigned_to, :status)
                    .order(:start_date)
                    .limit(8)

    children.map do |c|
      {
        id:       c.id,
        subject:  c.subject.truncate(50),
        progress: c.done_ratio || 0,
        assignee: c.assigned_to&.firstname || '-',
        stage:    nil
      }
    end
  end

  def build_customization_children(version_id)
    return [] if stage_field_id.blank?

    cr_issues = Issue.where(fixed_version_id: version_id, tracker_id: customization_tracker_id)
                     .includes(:status, :custom_values)
    return [] if cr_issues.empty?

    stage_groups = Hash.new { |h, k| h[k] = { total: 0, done: 0 } }
    cr_issues.each do |cr|
      stage = cf_value(cr, stage_field_id)
      stage = 'Backlog' if stage.blank?
      stage_groups[stage][:total] += 1
      stage_groups[stage][:done] += 1 if cr.status&.is_closed? || cr.done_ratio == 100
    end

    ordered_stages = %w[Backlog Design Develop Testing Deploy Closed]
    ordered_stages.filter_map do |stage_name|
      grp = stage_groups[stage_name]
      next unless grp
      pct = grp[:total] > 0 ? (grp[:done].to_f / grp[:total] * 100).round : 0
      {
        id:       nil,
        subject:  "#{stage_name} (#{grp[:done]}/#{grp[:total]})",
        progress: pct,
        assignee: nil,
        stage:    stage_name
      }
    end
  end

  def build_cr_pipeline
    return {} if customization_tracker_id == 0 || stage_field_id.blank?

    issues = Issue.open
                  .where(fixed_version_id: version_ids, tracker_id: customization_tracker_id)
                  .includes(:custom_values)

    pipeline = Hash.new(0)
    issues.each do |issue|
      stage = cf_value(issue, stage_field_id) || 'Backlog'
      pipeline[stage] += 1
    end

    ordered_stages = %w[Backlog Design Develop Testing Deploy]
    ordered_stages.each_with_object({}) do |stage, hash|
      hash[stage] = pipeline[stage] || 0
    end
  end

  def build_tracker_breakdown
    target_trackers = [customization_tracker_id, 15, 4].reject(&:zero?)
    counts = Issue.open
                  .where(fixed_version_id: version_ids)
                  .where(tracker_id: target_trackers)
                  .joins(:tracker)
                  .group('trackers.name')
                  .count

    counts.map { |name, count| { name: name, count: count } }
          .sort_by { |t| -t[:count] }
  end

  def build_team_hours
    base_entries = TimeEntry.where(issue_id: Issue.where(fixed_version_id: version_ids).select(:id))

    total = base_entries.sum(:hours).to_f.round(1)

    task_tracker_ids = [4]
    cr_tracker_ids = [customization_tracker_id, 15].reject(&:zero?)

    total_task = base_entries.joins(:issue).where(issues: { tracker_id: task_tracker_ids }).sum(:hours).to_f.round(1)
    total_cr = base_entries.joins(:issue).where(issues: { tracker_id: cr_tracker_ids }).sum(:hours).to_f.round(1)

    weeks_ago = 12
    start_date = weeks_ago.weeks.ago.beginning_of_week.to_date

    task_weekly = base_entries.joins(:issue)
                             .where(issues: { tracker_id: task_tracker_ids })
                             .where('spent_on >= ?', start_date)
                             .select("YEARWEEK(spent_on, 1) as yw, SUM(hours) as week_hours")
                             .group("YEARWEEK(spent_on, 1)")
    task_map = {}
    task_weekly.each { |e| task_map[e.yw.to_s] = e.week_hours.to_f.round(1) }

    cr_weekly = base_entries.joins(:issue)
                            .where(issues: { tracker_id: cr_tracker_ids })
                            .where('spent_on >= ?', start_date)
                            .select("YEARWEEK(spent_on, 1) as yw, SUM(hours) as week_hours")
                            .group("YEARWEEK(spent_on, 1)")
    cr_map = {}
    cr_weekly.each { |e| cr_map[e.yw.to_s] = e.week_hours.to_f.round(1) }

    weeks = []
    (0...weeks_ago).each do |i|
      week_start = (start_date + i.weeks)
      yw = week_start.strftime('%G%V')
      week_end = week_start + 6.days
      label = "#{week_start.strftime('%d%b')}-#{week_end.strftime('%d%b')}"
      weeks << { label: label, task: task_map[yw] || 0, cr: cr_map[yw] || 0 }
    end

    { weeks: weeks, total: total, total_task: total_task, total_cr: total_cr }
  end

  def build_active_crs
    return [] if customization_tracker_id == 0

    issues = Issue.open
                  .where(fixed_version_id: version_ids, tracker_id: customization_tracker_id)
                  .includes(:assigned_to, :status, :custom_values)
                  .order(due_date: :asc)
                  .limit(10)

    issues.map do |issue|
      {
        id:        issue.id,
        cr_id:     cf_value(issue, settings['cr_field_id']),
        subject:   issue.subject.truncate(50),
        assignee:  issue.assigned_to&.firstname || '-',
        stage:     cf_value(issue, stage_field_id) || 'Backlog',
        due_date:  issue.due_date&.to_s,
        progress:  issue.done_ratio || 0,
        is_overdue: issue.due_date && issue.due_date < Date.today
      }
    end
  end
end

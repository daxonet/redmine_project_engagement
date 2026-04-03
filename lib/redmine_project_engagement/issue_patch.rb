module RedmineProjectEngagement
  module IssuePatch
    def self.included(base)
      base.class_eval do
        before_validation :inherit_parent_version, on: :create
        after_create :create_stage_subtasks
        after_save :advance_parent_stage_on_close
      end
    end

    private

    def inherit_parent_version
      return unless parent_id.present? && fixed_version_id.blank?
      parent_issue = Issue.find_by(id: parent_id)
      self.fixed_version_id = parent_issue.fixed_version_id if parent_issue&.fixed_version_id
    end

    def plugin_settings
      @_pe_settings ||= Setting.plugin_redmine_project_engagement || {}
    end

    def customization_tracker_id
      plugin_settings['customization_tracker_id'].to_i
    end

    def subtask_tracker_id
      plugin_settings['customization_subtask_tracker_id'].to_i
    end

    def stage_field_id
      plugin_settings['stage_field_id'].to_i
    end

    def stage_list
      val = plugin_settings['stage_subtask_list']
      if val.is_a?(Array)
        val.reject(&:blank?)
      else
        (val || '').split(',').map(&:strip).reject(&:blank?)
      end
    end

    # After creating a Customization issue, auto-create stage subtasks
    def create_stage_subtasks
      return if customization_tracker_id == 0 || subtask_tracker_id == 0
      return unless tracker_id == customization_tracker_id
      return if stage_list.empty?

      new_status = IssueStatus.where(is_closed: false).order(:position).first

      stage_list.each do |stage|
        sub = Issue.create(
          project_id: project_id,
          tracker_id: subtask_tracker_id,
          subject: "[#{stage}] #{subject.truncate(80)}",
          parent_id: id,
          status: new_status,
          author_id: author_id,
          assigned_to_id: assigned_to_id,
          start_date: start_date,
          due_date: due_date,
          fixed_version_id: fixed_version_id
        )
        # Set subtask's Stage field to match its stage
        if sub.persisted? && stage_field_id > 0
          cv = CustomValue.where(customized_type: 'Issue', customized_id: sub.id, custom_field_id: stage_field_id).first_or_initialize
          cv.value = stage
          cv.save
        end
      end
    end

    # When a stage subtask is closed, advance parent CR's stage to next
    def advance_parent_stage_on_close
      return unless saved_change_to_status_id?
      return unless status&.is_closed?
      return if parent_id.blank?
      return if stage_field_id == 0 || stage_list.empty?

      parent_issue = Issue.find_by(id: parent_id)
      return unless parent_issue
      return unless parent_issue.tracker_id == customization_tracker_id

      # Determine which stage this subtask represents
      current_stage = nil
      stage_list.each do |stage|
        if subject.downcase.include?("[#{stage.downcase}]")
          current_stage = stage
          break
        end
      end
      return unless current_stage

      # Check if all subtasks for this stage are closed
      stage_subs = Issue.where(parent_id: parent_id).where("LOWER(subject) LIKE ?", "%[#{current_stage.downcase}]%")
      return unless stage_subs.all? { |s| s.status&.is_closed? }

      # Find next stage
      current_idx = stage_list.index(current_stage)
      return unless current_idx

      next_stage = stage_list[current_idx + 1]

      # Update parent's stage field
      cv = CustomValue.where(customized_type: 'Issue', customized_id: parent_id, custom_field_id: stage_field_id).first_or_create
      if next_stage
        cv.update(value: next_stage)
      else
        # All stages done - set to Deploy (or last+1 stage)
        cv.update(value: 'Deploy')
      end
    end
  end
end

unless Issue.included_modules.include?(RedmineProjectEngagement::IssuePatch)
  Issue.send(:include, RedmineProjectEngagement::IssuePatch)
end

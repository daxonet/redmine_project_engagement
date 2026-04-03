module EngagementContractsHelper
  def format_contract_hours(hours)
    return '-' if hours.nil?
    mandays = (hours / 8.0).round(1)
    "#{hours.to_i} hours / #{mandays} mandays"
  end

  def engagement_contract_status_label(status)
    case status
    when 'open'
      content_tag(:span, l(:label_open), class: 'badge badge-success')
    when 'closed'
      content_tag(:span, l(:label_closed), class: 'badge badge-secondary')
    end
  end

  def version_type_label(version)
    parts = []
    parts << version.version_type if version.version_type.present?
    parts << version.version_sub_type if version.version_sub_type.present?
    parts.join(' - ')
  end

  def version_type_options
    [['', ''], ['Sprint', 'Sprint'], ['Milestone', 'Milestone']]
  end

  def version_sub_type_options
    [['', ''],
     ['Customization', 'Customization'],
     ['Go-Live', 'Go-Live'],
     ['Post-Live-Support', 'Post-Live-Support'],
     ['Additional-Scope', 'Additional-Scope'],
     ['Project-Management', 'Project-Management']]
  end
end

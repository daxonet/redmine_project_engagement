module RedmineProjectEngagement
  module VersionPatch
    ENGAGEMENT_VERSION_TYPES = %w[Sprint Milestone].freeze
    ENGAGEMENT_VERSION_SUB_TYPES = %w[Customization Go-Live Post-Live-Support Additional-Scope Project-Management].freeze

    def self.included(base)
      base.class_eval do
        belongs_to :engagement_contract, optional: true

        safe_attributes 'planned_start_date', 'version_type', 'version_sub_type', 'engagement_contract_id'

        validates :version_type, inclusion: { in: ENGAGEMENT_VERSION_TYPES }, allow_blank: true
        validates :version_sub_type, inclusion: { in: ENGAGEMENT_VERSION_SUB_TYPES }, allow_blank: true
        validate :sub_type_requires_milestone

        private

        def sub_type_requires_milestone
          if version_sub_type.present? && version_type != 'Milestone'
            errors.add(:version_sub_type, :invalid)
          end
        end
      end
    end
  end
end

unless Version.included_modules.include?(RedmineProjectEngagement::VersionPatch)
  Version.send(:include, RedmineProjectEngagement::VersionPatch)
end

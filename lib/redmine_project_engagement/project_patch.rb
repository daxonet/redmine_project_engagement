module RedmineProjectEngagement
  module ProjectPatch
    def self.included(base)
      base.class_eval do
        has_many :engagement_contracts, dependent: :destroy
      end
    end
  end
end

unless Project.included_modules.include?(RedmineProjectEngagement::ProjectPatch)
  Project.send(:include, RedmineProjectEngagement::ProjectPatch)
end

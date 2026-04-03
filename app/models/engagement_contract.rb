class EngagementContract < ActiveRecord::Base
  belongs_to :project
  has_many :versions, foreign_key: :engagement_contract_id, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :project_id }
  validates :status, inclusion: { in: %w[open closed] }
  validates :contract_hours, numericality: { greater_than: 0 }, allow_nil: true

  before_create :generate_dashboard_secret

  scope :open, -> { where(status: 'open') }
  scope :closed, -> { where(status: 'closed') }

  def open?
    status == 'open'
  end

  def closed?
    status == 'closed'
  end

  def contract_mandays
    return nil unless contract_hours
    (contract_hours / 8.0).round(1)
  end

  def reset_dashboard_secret!
    update!(dashboard_secret: SecureRandom.hex(16), dashboard_secret_created_at: Time.current)
  end

  def ensure_dashboard_secret
    if dashboard_secret.blank?
      now = Time.current
      update_columns(dashboard_secret: SecureRandom.hex(16), dashboard_secret_created_at: now)
    end
    dashboard_secret
  end

  def sorted_versions
    versions.order(Arel.sql("CASE WHEN versions.version_sub_type = 'Project-Management' THEN 0 WHEN versions.version_sub_type = 'Additional-Scope' THEN 2 ELSE 1 END ASC, COALESCE(versions.effective_date, '9999-12-31') ASC, COALESCE(versions.planned_start_date, '9999-12-31') ASC"))
  end

  private

  def generate_dashboard_secret
    self.dashboard_secret ||= SecureRandom.hex(16)
    self.dashboard_secret_created_at ||= Time.current
  end
end

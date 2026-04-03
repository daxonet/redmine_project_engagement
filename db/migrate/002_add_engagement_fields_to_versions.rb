class AddEngagementFieldsToVersions < ActiveRecord::Migration[7.0]
  def change
    add_column :versions, :engagement_contract_id, :integer
    add_column :versions, :planned_start_date, :date
    add_column :versions, :version_type, :string
    add_column :versions, :version_sub_type, :string

    add_index :versions, :engagement_contract_id
    add_foreign_key :versions, :engagement_contracts, on_delete: :nullify
  end
end

class CreateEngagementContracts < ActiveRecord::Migration[7.0]
  def change
    create_table :engagement_contracts, id: :integer do |t|
      t.integer :project_id, null: false
      t.string :name, null: false
      t.string :contract_number
      t.decimal :contract_hours, precision: 10, scale: 2
      t.date :contract_date
      t.text :description
      t.string :status, default: 'open', null: false
      t.string :dashboard_secret
      t.datetime :dashboard_secret_created_at
      t.datetime :created_on
      t.datetime :updated_on
    end

    add_index :engagement_contracts, :project_id
    add_index :engagement_contracts, [:project_id, :name], unique: true
    add_foreign_key :engagement_contracts, :projects
  end
end

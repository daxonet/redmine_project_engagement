# Redmine Project Engagement

A Redmine 6.0 plugin for managing project Engagement Contracts, version-based milestone tracking, and a real-time project dashboard.

## Features

### Engagement Contracts
- Create and manage Engagement Contracts per project (contract number, hours, date, status)
- Contract hours displayed as hours / mandays (1 manday = 8 hours)
- Roadmap-style version listing with progress bars, issue counts, and due dates
- Assign existing project versions or create new versions within a contract
- Role-based permission control (view, manage, share dashboard)

### Version Enhancement
- **Planned Start Date** field added to Redmine versions
- **Version Type**: Sprint or Milestone
- **Version Sub Type**: Customization, Go-Live, Post-Live-Support, Additional-Scope, Project-Management
- Fields visible in both the plugin's version form and Redmine's standard version edit page (when module is enabled)
- Sorting: Project-Management first, then by due date, Additional-Scope last

### Customization Workflow Automation
- Auto-create stage subtasks (e.g. Design, Develop, Testing) when a Customization issue is created
- Configurable stages via plugin settings (multi-select from Stage custom field values)
- Auto-advance parent CR stage when a stage subtask is closed
- Subtasks automatically inherit parent's target version

### Project Dashboard
- Dark-themed real-time command center (auto-refreshes every 5 minutes)
- **Phase Timeline**: horizontal bar showing all milestones with progress
- **Milestone Cards**: Previous / Current / Next with task details
  - Current phase auto-detected by progress (promotes to next when next phase progress > current remaining %)
  - Customization milestones show Design/Develop/Testing summary (done/total per stage)
  - Regular milestones show assigned open tasks (including subtasks with assignees)
- **Milestones List**: vertical timeline with status dots and due dates
- **Tracker Breakdown**: doughnut chart of open issues by tracker
- **Customization Status**: doughnut chart of CRs by stage (Backlog/Design/Develop/Testing/Deploy)
- **Time Spent**: stacked bar chart (Task vs CR) by week for last 12 weeks
- **Active Change Requests**: table of top 10 open CRs with stage badges and progress
- **KPIs**: Go-Live countdown, Open issues, Overdue, Waiting, Resolved (last 30 days)
- Configurable logo upload in plugin settings

### Dashboard Access
- **Authenticated**: requires Redmine login + `view_engagement_dashboard` permission
- **Public Share**: token-based URL, no login required
  - Share dialog with copy link, generated timestamp, and reset button
  - Reset invalidates all previously shared links
  - Controlled by `share_engagement_dashboard` permission

## Requirements

- Redmine 6.0+
- MySQL 8.0
- Ruby 3.x / Rails 7.2

## Installation

```bash
# Copy plugin to Redmine plugins directory
cp -r redmine_project_engagement /path/to/redmine/plugins/

# Run migrations
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# Restart Redmine
```

## Configuration

### 1. Enable Module
Go to **Project > Settings > Modules** and enable **Project Engagement**.

### 2. Plugin Settings
Go to **Administration > Plugins > Redmine Project Engagement > Configure**:

| Setting | Description |
|---------|-------------|
| Customization Tracker | Tracker used for Change Requests (e.g. "Customization") |
| Customization Subtask Tracker | Tracker for auto-created stage subtasks (e.g. "Subtask") |
| Stage Field | Issue custom field (list type) for CR stage (e.g. "Stage") |
| Stage Subtask List | Select which stages auto-create subtasks on CR creation |
| Dashboard Logo | Upload logo image (PNG recommended) for dashboard header |

### 3. Role Permissions
Go to **Administration > Roles and permissions > Project Engagement**:

| Permission | Description |
|------------|-------------|
| View engagement contracts | View contract list and details |
| View dashboard | Open the authenticated dashboard |
| Share dashboard link | Access share dialog, copy/reset public link |
| Manage engagement contracts | Create/edit/delete contracts, assign/remove versions |
| Manage engagement contract versions | Create/edit/delete versions within contracts |

## Database Schema

### New Table: `engagement_contracts`
| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| project_id | integer | FK to projects |
| name | string | Contract name |
| contract_number | string | PO/contract number |
| contract_hours | decimal(10,2) | Total contracted hours |
| contract_date | date | Contract date |
| description | text | Description |
| status | string | open / closed |
| dashboard_secret | string | Secret for public dashboard token |
| dashboard_secret_created_at | datetime | When the share link was generated |

### Columns Added to `versions`
| Column | Type | Description |
|--------|------|-------------|
| engagement_contract_id | integer | FK to engagement_contracts |
| planned_start_date | date | Version start date |
| version_type | string | Sprint / Milestone |
| version_sub_type | string | Customization / Go-Live / Post-Live-Support / Additional-Scope / Project-Management |

## Routes

### Engagement Contracts
```
GET    /projects/:project_id/engagement_contracts           # index
GET    /projects/:project_id/engagement_contracts/:id        # show
POST   /projects/:project_id/engagement_contracts            # create
PATCH  /projects/:project_id/engagement_contracts/:id        # update
DELETE /projects/:project_id/engagement_contracts/:id        # destroy
POST   /projects/:project_id/engagement_contracts/:id/add_version
DELETE /projects/:project_id/engagement_contracts/:id/remove_version
POST   /projects/:project_id/engagement_contracts/:id/reset_dashboard_link
```

### Version Management (within contract)
```
GET    /projects/:project_id/engagement_contracts/:id/versions/new
POST   /projects/:project_id/engagement_contracts/:id/versions
GET    /projects/:project_id/engagement_contracts/:id/versions/:id/edit
PATCH  /projects/:project_id/engagement_contracts/:id/versions/:id
DELETE /projects/:project_id/engagement_contracts/:id/versions/:id
```

### Dashboard
```
GET    /projects/:project_id/engagement_contracts/:id/dashboard     # authenticated
GET    /engagement_dashboard/:project_id/:ec_id/:token              # public (token)
GET    /engagement_dashboard/:project_id/:ec_id/:token/data         # public JSON
```

## Docker Development

```bash
# Start (imports test SQL on first run)
docker compose up -d

# Wait for DB healthy, then run migrations
docker compose exec redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# Restart to pick up changes
docker compose restart redmine
```

Ports: Redmine on `3081`, MySQL on `3308`.

## Plugin Structure

```
redmine_project_engagement/
  init.rb                                    # Plugin registration
  config/
    routes.rb                                # All routes
    locales/en.yml                           # English translations
  db/migrate/
    001_create_engagement_contracts.rb       # engagement_contracts table
    002_add_engagement_fields_to_versions.rb # Version extensions
  app/
    models/
      engagement_contract.rb                 # EngagementContract model
    controllers/
      engagement_contracts_controller.rb     # CRUD + version management
      engagement_contract_versions_controller.rb  # Version CRUD
      engagement_dashboard_controller.rb     # Dashboard + logo upload
    helpers/
      engagement_contracts_helper.rb         # Format helpers
    views/
      engagement_contracts/                  # Contract views (index/show/new/edit)
      engagement_contract_versions/          # Version form views
      engagement_dashboard/                  # Dashboard (show + styles)
      versions/_form.html.erb               # Override Redmine version form
      settings/_redmine_project_engagement.html.erb  # Plugin settings
  lib/redmine_project_engagement/
    version_patch.rb    # Adds fields + validations to Version
    project_patch.rb    # Adds has_many :engagement_contracts to Project
    issue_patch.rb      # Auto-create subtasks + stage advancement
  assets/
    stylesheets/project_engagement.css      # Roadmap + dialog styles
    javascripts/project_engagement.js
  docker-compose.yml                         # Dev environment
```

## License

This plugin is open source.

## Author

**LS MARK** - [DAXONET](https://daxonet.com)

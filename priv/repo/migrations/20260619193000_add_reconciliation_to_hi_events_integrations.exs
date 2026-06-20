defmodule Claper.Repo.Migrations.AddReconciliationToHiEventsIntegrations do
  use Ecto.Migration

  def change do
    alter table(:hi_events_integrations) do
      add :remote_webhook_id, :string
      add :last_reconciled_at, :utc_datetime
      add :last_reconcile_status, :string
    end
  end
end

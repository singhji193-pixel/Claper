defmodule Claper.Repo.Migrations.AddPublicIdToHiEventsTickets do
  use Ecto.Migration

  def up do
    alter table(:hi_events_tickets) do
      add :external_public_id, :string
    end

    # Backfill from the retained webhook payload so existing tickets get a
    # scannable Hi.Events public_id without waiting for reconciliation.
    execute """
    UPDATE hi_events_tickets
    SET external_public_id = raw_payload->>'public_id'
    WHERE raw_payload ? 'public_id'
      AND external_public_id IS NULL
    """
  end

  def down do
    alter table(:hi_events_tickets) do
      remove :external_public_id
    end
  end
end

defmodule Claper.EventApp.TimeTest do
  use ExUnit.Case, async: true

  alias Claper.EventApp.Time, as: EventTime

  describe "valid_timezone?/1" do
    test "accepts IANA zone names" do
      assert EventTime.valid_timezone?("America/Vancouver")
      assert EventTime.valid_timezone?("UTC")
    end

    test "rejects unknown or blank values" do
      refute EventTime.valid_timezone?("Not/AZone")
      refute EventTime.valid_timezone?("")
      refute EventTime.valid_timezone?(nil)
    end
  end

  describe "to_utc/2" do
    test "converts Pacific daylight wall time to UTC" do
      assert EventTime.to_utc(~N[2026-07-25 08:30:00], "America/Vancouver") ==
               ~N[2026-07-25 15:30:00]
    end

    test "converts Pacific standard wall time to UTC" do
      assert EventTime.to_utc(~N[2026-01-15 08:30:00], "America/Vancouver") ==
               ~N[2026-01-15 16:30:00]
    end

    test "resolves nonexistent wall times during spring-forward to just after the gap" do
      assert EventTime.to_utc(~N[2026-03-08 02:30:00], "America/Vancouver") ==
               ~N[2026-03-08 10:00:00]
    end

    test "resolves ambiguous fall-back wall times to the earlier instant" do
      assert EventTime.to_utc(~N[2026-11-01 01:30:00], "America/Vancouver") ==
               ~N[2026-11-01 08:30:00]
    end

    test "returns the input unchanged for an invalid timezone" do
      assert EventTime.to_utc(~N[2026-07-25 08:30:00], "Bogus/Zone") ==
               ~N[2026-07-25 08:30:00]
    end

    test "passes nil through" do
      assert EventTime.to_utc(nil, "America/Vancouver") == nil
    end
  end

  describe "to_local/2" do
    test "converts UTC to Pacific daylight wall time" do
      assert EventTime.to_local(~N[2026-07-26 00:15:00], "America/Vancouver") ==
               ~N[2026-07-25 17:15:00]
    end

    test "returns the input unchanged for an invalid timezone" do
      assert EventTime.to_local(~N[2026-07-26 00:15:00], "Bogus/Zone") ==
               ~N[2026-07-26 00:15:00]
    end

    test "passes nil through" do
      assert EventTime.to_local(nil, "America/Vancouver") == nil
    end
  end

  describe "local_date/2" do
    test "returns the event-local calendar date for a UTC timestamp" do
      assert EventTime.local_date(~N[2026-07-26 00:15:00], "America/Vancouver") ==
               ~D[2026-07-25]
    end
  end
end

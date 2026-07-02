# Creates a deterministic OTP challenge for an e2e attendee login.
#
#   docker exec clapper-app-1 mix run e2e/otp.exs <email> [code]
#
# Deletes previous challenges for the email first so OTP rate limiting and
# request spacing never block a test run. Dev use only.

import Ecto.Query

alias Claper.{EventApp, Repo}
alias Claper.EventApp.OtpChallenge

[email | rest] = System.argv()
code = List.first(rest) || "4821"

event =
  Claper.Events.get_event_with_code("e2e01") ||
    raise "e2e01 event missing - run e2e/seed.exs first"

Repo.delete_all(from(c in OtpChallenge, where: c.event_id == ^event.id and c.email == ^email))

{:ok, _result} = EventApp.request_login_code("e2e01", email, code: code)

IO.puts("otp ready for #{email}")

defmodule ClaperWeb.CollabReveal do
  @moduledoc """
  A self-contained Swing-In Doors logo collaboration reveal for the presenter.

  Phoenix renders the stage and QR slot. CSS owns the motion, while a small
  LiveView hook advances the sponsor only when the cards are fully hidden.
  """

  use Phoenix.Component

  attr :id, :string, default: "collab-reveal"
  attr :logo_a, :string, required: true
  attr :logo_a_alt, :string, default: "NextGEN Business Summit"
  attr :welcome, :string, default: "Welcome to NextGEN"
  attr :sponsor_label, :string, default: "With support from"
  attr :partner_label, :string, default: "In collaboration with"
  attr :join_url, :string, required: true
  attr :join_code, :string, required: true
  attr :footer_left, :string, default: "NextGEN Business Summit 2026"
  attr :footer_right, :string, default: "Anvil Centre, New Westminster"
  attr :accent, :string, default: "#E8C96A"
  attr :card_pane, :string, default: "#F7F5EF"
  attr :duration, :string, default: "8s"
  attr :styles, :boolean, default: true
  attr :class, :string, default: nil
  attr :rest, :global

  slot :sponsor, required: true do
    attr :name, :string, required: true
    attr :role, :string, required: true
    attr :logo, :string, required: true
    attr :dark, :boolean
    attr :kind, :string
  end

  slot :qr, required: true

  def swing_doors(assigns) do
    first_sponsor = List.first(assigns.sponsor)

    assigns =
      assigns
      |> assign(:first_sponsor, first_sponsor)
      |> assign(:first_sponsor_kind, Map.get(first_sponsor, :kind, "sponsor"))

    ~H"""
    <div
      id={@id}
      phx-hook="SponsorReveal"
      class={["cr-wrap", @class]}
      style={"--accent:#{@accent};--pane:#{@card_pane};--cr-dur:#{@duration}"}
      data-sponsor-label={@sponsor_label}
      data-partner-label={@partner_label}
      {@rest}
    >
      <style :if={@styles}>
        @font-face {
          font-family: 'NextGEN Fraunces';
          font-style: normal;
          font-weight: 300 900;
          font-display: swap;
          src: url('/fonts/nextgen/fraunces-variable.woff2') format('woff2');
        }

        @font-face {
          font-family: 'NextGEN Poppins';
          font-style: normal;
          font-weight: 400;
          font-display: swap;
          src: url('/fonts/nextgen/poppins-400.woff2') format('woff2');
        }

        @font-face {
          font-family: 'NextGEN Poppins';
          font-style: normal;
          font-weight: 500;
          font-display: swap;
          src: url('/fonts/nextgen/poppins-500.woff2') format('woff2');
        }

        @font-face {
          font-family: 'NextGEN Poppins';
          font-style: normal;
          font-weight: 600;
          font-display: swap;
          src: url('/fonts/nextgen/poppins-600.woff2') format('woff2');
        }

        @font-face {
          font-family: 'NextGEN JetBrains Mono';
          font-style: normal;
          font-weight: 400 600;
          font-display: swap;
          src: url('/fonts/nextgen/jetbrains-mono-variable.woff2') format('woff2');
        }

        .cr-wrap {
          --accent: #E8C96A;
          --bright: #F6DF9F;
          --pane: #F7F5EF;
          --cr-dur: 8s;
          --font-display: 'NextGEN Fraunces', Georgia, serif;
          --font-body: 'NextGEN Poppins', Arial, sans-serif;
          --font-mono: 'NextGEN JetBrains Mono', 'Courier New', monospace;
          --play: running;
          display: flex;
          width: 100%;
          height: 100%;
          min-height: 100dvh;
          align-items: center;
          justify-content: center;
          padding: 24px;
          overflow: hidden;
          color: #F4ECD8;
          background: #0B0A09;
          font-family: var(--font-body);
        }

        .cr-stage {
          position: relative;
          display: grid;
          grid-template-columns: 1fr 1fr;
          width: min(1200px, calc(100vw - 48px), calc((100dvh - 48px) * 16 / 9));
          max-width: 100%;
          aspect-ratio: 16 / 9;
          overflow: hidden;
          background:
            radial-gradient(
              120% 90% at 25% 60%,
              rgba(201, 168, 76, .10),
              rgba(6, 6, 5, 0) 60%
            ),
            #060605;
          border: 1px solid rgba(201, 168, 76, .2);
          border-radius: 20px;
          box-shadow:
            0 34px 90px -34px rgba(0, 0, 0, .85),
            inset 0 0 0 1px rgba(201, 168, 76, .06);
        }

        .cr-divider {
          position: absolute;
          top: 9%;
          bottom: 9%;
          left: 50%;
          z-index: 2;
          width: 1px;
          pointer-events: none;
          transform: translateX(-50%);
          background: linear-gradient(
            to bottom,
            rgba(201, 168, 76, 0),
            rgba(201, 168, 76, .4),
            rgba(201, 168, 76, 0)
          );
        }

        .cr-left {
          position: relative;
          display: flex;
          flex-direction: column;
          gap: 30px;
          align-items: center;
          justify-content: center;
          padding: 40px;
          perspective: 1200px;
          perspective-origin: 50% 46%;
        }

        .cr-welcome {
          position: absolute;
          top: 32px;
          left: 34px;
          z-index: 1;
          color: rgba(246, 223, 159, .96);
          font-family: var(--font-display);
          font-size: clamp(24px, 2vw, 30px);
          font-weight: 500;
          line-height: .94;
          letter-spacing: -.025em;
          white-space: nowrap;
        }

        .cr-floor {
          position: absolute;
          right: 0;
          bottom: 16%;
          left: 0;
          height: 40%;
          pointer-events: none;
          background: radial-gradient(
            60% 100% at 50% 100%,
            rgba(201, 168, 76, .14),
            rgba(6, 6, 5, 0) 70%
          );
        }

        .cr-dust {
          position: absolute;
          background: var(--accent);
          border-radius: 50%;
        }

        .cr-dust.d1 {
          top: 26%;
          left: 22%;
          width: 3px;
          height: 3px;
          opacity: .5;
          animation: crFloat 5.5s ease-in-out infinite alternate;
        }

        .cr-dust.d2 {
          top: 64%;
          right: 20%;
          width: 2px;
          height: 2px;
          opacity: .4;
          animation: crFloat 6.5s ease-in-out 1s infinite alternate;
        }

        .cr-lockup {
          position: relative;
          display: flex;
          gap: 16px;
          align-items: center;
          justify-content: center;
          transform-style: preserve-3d;
        }

        .cr-card {
          position: relative;
          width: 206px;
          height: 146px;
          overflow: hidden;
          background: var(--pane);
          border: 1px solid rgba(201, 168, 76, .35);
          border-radius: 14px;
          box-shadow: 0 20px 46px -20px rgba(0, 0, 0, .8);
          backface-visibility: hidden;
          transform-style: preserve-3d;
        }

        .cr-card.is-dark,
        .cr-card--l {
          background: #0D0B08;
        }

        .cr-card img {
          position: absolute;
          inset: 0;
          display: block;
          width: 100%;
          height: 100%;
          padding: 16px;
          object-fit: contain;
        }

        .cr-card--l {
          animation: crSwingL var(--cr-dur) cubic-bezier(.5, .05, .2, 1) infinite both;
        }

        .cr-card--r {
          animation: crSwingR var(--cr-dur) cubic-bezier(.5, .05, .2, 1) infinite both;
        }

        .cr-x {
          position: relative;
          display: flex;
          flex: 0 0 auto;
          width: 66px;
          height: 66px;
          align-items: center;
          justify-content: center;
          animation: crXPop var(--cr-dur) cubic-bezier(.34, 1.56, .64, 1) infinite both;
        }

        .cr-x span {
          position: relative;
          color: var(--bright);
          font-family: var(--font-display);
          font-size: 58px;
          font-weight: 500;
          line-height: 1;
          text-shadow: 0 2px 18px rgba(232, 201, 106, .5);
        }

        .cr-glow {
          position: absolute;
          width: 120px;
          height: 120px;
          background: radial-gradient(
            50% 50% at 50% 50%,
            rgba(232, 201, 106, .55),
            rgba(232, 201, 106, 0) 70%
          );
          border-radius: 50%;
          animation: crGlow var(--cr-dur) ease-in-out infinite both;
        }

        .cr-eye {
          text-align: center;
          animation: crEye var(--cr-dur) ease-in-out infinite both;
        }

        .cr-eye__label {
          color: var(--accent);
          font-family: var(--font-mono);
          font-size: 11px;
          font-weight: 600;
          letter-spacing: .28em;
          text-transform: uppercase;
        }

        .cr-eye__rule {
          width: 54px;
          height: 2px;
          margin: 12px auto 0;
          background: linear-gradient(
            90deg,
            rgba(201, 168, 76, 0),
            var(--bright),
            rgba(201, 168, 76, 0)
          );
        }

        .cr-right {
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 40px 48px 68px;
        }

        .cr-join {
          position: relative;
          width: 100%;
          max-width: 410px;
          padding: clamp(24px, 2.2vw, 40px);
          overflow: hidden;
          color: #F8F4EC;
          background:
            linear-gradient(150deg, rgba(18, 16, 11, .98), rgba(8, 8, 6, .98));
          border: 1px solid rgba(201, 168, 76, .38);
          box-shadow:
            0 26px 80px rgba(0, 0, 0, .32),
            inset 0 1px 0 rgba(246, 223, 159, .06);
        }

        .cr-join::before {
          position: absolute;
          top: -46%;
          left: -18%;
          width: 62%;
          height: 190%;
          pointer-events: none;
          content: '';
          background: linear-gradient(
            90deg,
            rgba(246, 223, 159, 0),
            rgba(246, 223, 159, .07),
            rgba(246, 223, 159, 0)
          );
          transform: rotate(18deg);
        }

        .cr-join__kicker {
          position: relative;
          color: var(--bright);
          font-family: var(--font-mono);
          font-size: clamp(9px, .61vw, 12px);
          font-weight: 600;
          letter-spacing: .19em;
          text-transform: uppercase;
        }

        .cr-join h2 {
          position: relative;
          max-width: 340px;
          margin: clamp(13px, 1.2vw, 20px) 0 0;
          color: #F8F4EC;
          font-family: var(--font-display);
          font-size: clamp(32px, 2.35vw, 48px);
          font-weight: 500;
          line-height: 1.04;
          letter-spacing: -.045em;
        }

        .cr-join__copy {
          position: relative;
          max-width: 330px;
          margin: 12px 0 0;
          color: rgba(248, 244, 236, .58);
          font-family: var(--font-body);
          font-size: clamp(12px, .78vw, 16px);
          line-height: 1.55;
        }

        .cr-qr-frame {
          position: relative;
          display: grid;
          width: fit-content;
          padding: clamp(8px, .7vw, 12px);
          margin: clamp(18px, 2vh, 26px) auto 0;
          background: #FFFDF8;
          border: 1px solid rgba(232, 201, 106, .7);
          place-items: center;
          box-shadow:
            0 18px 44px rgba(0, 0, 0, .34),
            0 0 28px rgba(232, 201, 106, .08);
        }

        .cr-qr {
          display: flex;
          width: clamp(170px, 16vw, 236px);
          aspect-ratio: 1;
          align-items: center;
          justify-content: center;
          overflow: hidden;
          background: #fff;
        }

        .cr-qr-content {
          display: flex;
          width: 100%;
          height: 100%;
          align-items: center;
          justify-content: center;
          overflow: hidden;
          background: #fff;
        }

        .cr-qr-content canvas {
          display: block;
          width: 100% !important;
          height: 100% !important;
        }

        .cr-join__code {
          position: relative;
          display: grid;
          gap: 4px;
          margin-top: clamp(14px, 1.5vw, 22px);
          text-align: center;
        }

        .cr-join__code p {
          margin: 0;
          color: rgba(248, 244, 236, .5);
          font-family: var(--font-mono);
          font-size: clamp(8px, .52vw, 10px);
          font-weight: 600;
          letter-spacing: .19em;
          text-transform: uppercase;
        }

        .cr-join__code strong {
          max-width: 100%;
          overflow: hidden;
          color: #F8F4EC;
          font-family: var(--font-mono);
          font-size: clamp(30px, 2.55vw, 50px);
          font-weight: 600;
          line-height: 1;
          letter-spacing: .08em;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .cr-join__note {
          position: relative;
          margin: clamp(12px, 1.2vw, 18px) 0 0;
          color: rgba(248, 244, 236, .48);
          font-family: var(--font-body);
          font-size: clamp(9px, .61vw, 12px);
          font-weight: 500;
          line-height: 1.4;
          text-align: center;
        }

        .cr-footer {
          position: absolute;
          right: 32px;
          bottom: 18px;
          left: 32px;
          z-index: 3;
          display: flex;
          gap: 24px;
          align-items: center;
          justify-content: space-between;
          color: rgba(248, 244, 236, .7);
          font-family: var(--font-mono);
          font-size: clamp(10px, .78vw, 13px);
          font-weight: 600;
          letter-spacing: .12em;
          text-transform: uppercase;
        }

        .cr-footer span {
          font-family: var(--font-mono);
        }

        .cr-footer span:last-child {
          text-align: right;
        }

        .cr-active-sponsor-meta {
          position: absolute;
          width: 1px;
          height: 1px;
          padding: 0;
          margin: -1px;
          overflow: hidden;
          clip: rect(0, 0, 0, 0);
          white-space: nowrap;
          border: 0;
        }

        @keyframes crSwingL {
          0% {
            opacity: 0;
            transform: translateX(-95%) rotateY(-105deg);
          }
          15% {
            opacity: 1;
            transform: translateX(0) rotateY(0);
          }
          82% {
            opacity: 1;
            transform: translateX(0) rotateY(0);
          }
          97% {
            opacity: 0;
            transform: translateX(-45%) rotateY(90deg);
          }
          100% {
            opacity: 0;
            transform: translateX(-95%) rotateY(-105deg);
          }
        }

        @keyframes crSwingR {
          0% {
            opacity: 0;
            transform: translateX(95%) rotateY(105deg);
          }
          15% {
            opacity: 1;
            transform: translateX(0) rotateY(0);
          }
          82% {
            opacity: 1;
            transform: translateX(0) rotateY(0);
          }
          97% {
            opacity: 0;
            transform: translateX(45%) rotateY(-90deg);
          }
          100% {
            opacity: 0;
            transform: translateX(95%) rotateY(105deg);
          }
        }

        @keyframes crXPop {
          0%, 15% {
            opacity: 0;
            transform: scale(0) rotate(-180deg);
          }
          23% {
            opacity: 1;
            transform: scale(1.3) rotate(0deg);
          }
          30% {
            opacity: 1;
            transform: scale(1) rotate(0deg);
          }
          82% {
            opacity: 1;
            transform: scale(1) rotate(0deg);
          }
          96% {
            opacity: 0;
            transform: scale(.3) rotate(60deg);
          }
          100% {
            opacity: 0;
            transform: scale(0) rotate(-180deg);
          }
        }

        @keyframes crGlow {
          0%, 16% {
            opacity: 0;
            transform: scale(.4);
          }
          24% {
            opacity: .85;
            transform: scale(1.15);
          }
          42% {
            opacity: .32;
            transform: scale(1);
          }
          82% {
            opacity: .32;
          }
          96%, 100% {
            opacity: 0;
          }
        }

        @keyframes crEye {
          0%, 22% {
            opacity: 0;
            transform: translateY(9px);
          }
          32% {
            opacity: 1;
            transform: none;
          }
          82% {
            opacity: 1;
          }
          96%, 100% {
            opacity: 0;
          }
        }

        @keyframes crFloat {
          from {
            transform: translateY(5px);
          }
          to {
            transform: translateY(-11px);
          }
        }

        @media (max-width: 980px) {
          .cr-wrap {
            padding: 16px;
          }

          .cr-stage {
            width: min(1200px, calc(100vw - 32px), calc((100dvh - 32px) * 16 / 9));
          }

          .cr-left,
          .cr-right {
            padding: 24px;
          }

          .cr-left {
            gap: 18px;
          }

          .cr-welcome {
            top: 20px;
            left: 20px;
            font-size: 18px;
          }

          .cr-lockup {
            transform: scale(.68);
          }

          .cr-right {
            padding-bottom: 46px;
          }

          .cr-join {
            max-width: 330px;
            padding: 18px;
          }

          .cr-qr {
            width: 150px;
          }

          .cr-join__code strong {
            font-size: 28px;
          }

          .cr-footer {
            right: 20px;
            bottom: 11px;
            left: 20px;
            font-size: 9px;
          }
        }

        @media (max-width: 600px) {
          .cr-wrap {
            padding: 8px;
          }

          .cr-stage {
            width: min(1200px, calc(100vw - 16px), calc((100dvh - 16px) * 16 / 9));
            border-radius: 12px;
          }

          .cr-left,
          .cr-right {
            padding: 10px;
          }

          .cr-left {
            gap: 6px;
          }

          .cr-welcome {
            top: 10px;
            left: 12px;
            font-size: 14px;
          }

          .cr-lockup {
            transform: scale(.34);
          }

          .cr-eye__label {
            font-size: 6px;
          }

          .cr-eye__rule {
            width: 30px;
            margin-top: 5px;
          }

          .cr-right {
            padding-bottom: 24px;
          }

          .cr-join {
            max-width: 240px;
            padding: 10px;
          }

          .cr-join__kicker {
            font-size: 5px;
          }

          .cr-join h2 {
            margin-top: 4px;
            font-size: 14px;
          }

          .cr-join__copy {
            margin-top: 4px;
            font-size: 6px;
            line-height: 1.3;
          }

          .cr-qr-frame {
            padding: 4px;
            margin-top: 6px;
          }

          .cr-qr {
            width: 70px;
          }

          .cr-join__code {
            gap: 1px;
            margin-top: 6px;
          }

          .cr-join__code p {
            font-size: 4px;
          }

          .cr-join__code strong {
            font-size: 12px;
          }

          .cr-join__note {
            margin-top: 4px;
            font-size: 5px;
          }

          .cr-footer {
            right: 10px;
            bottom: 6px;
            left: 10px;
            gap: 8px;
            font-size: 7px;
          }
        }

        @media (prefers-reduced-motion: reduce) {
          .cr-card--l,
          .cr-card--r,
          .cr-x,
          .cr-glow,
          .cr-eye,
          .cr-dust {
            animation: none !important;
          }

          .cr-card--l,
          .cr-card--r,
          .cr-x,
          .cr-eye {
            opacity: 1;
            transform: none;
          }

          .cr-glow {
            opacity: .32;
          }
        }
      </style>

      <div class="cr-stage">
        <div class="cr-divider"></div>

        <div class="cr-left">
          <div class="cr-floor"></div>
          <div class="cr-welcome">{@welcome}</div>
          <div class="cr-dust d1" data-anim></div>
          <div class="cr-dust d2" data-anim></div>

          <div class="cr-lockup">
            <div class="cr-card cr-card--l" data-anim>
              <img src={@logo_a} alt={@logo_a_alt} />
            </div>

            <div class="cr-x" data-anim>
              <div class="cr-glow" data-anim></div>
              <span>&times;</span>
            </div>

            <div
              class={[
                "cr-card cr-card--r",
                Map.get(@first_sponsor, :dark, false) && "is-dark"
              ]}
              data-active-sponsor-card
              data-anim
            >
              <img
                src={@first_sponsor.logo}
                alt={"#{@first_sponsor.name} logo"}
                data-active-sponsor-logo
              />
            </div>
          </div>

          <div class="cr-eye" data-anim aria-live="polite">
            <div class="cr-eye__label" data-active-sponsor-label>
              {if @first_sponsor_kind == "partner",
                do: @partner_label,
                else: @sponsor_label}
            </div>
            <div class="cr-eye__rule"></div>
            <span class="cr-active-sponsor-meta" data-active-sponsor-role>
              {@first_sponsor.role}
            </span>
            <span class="cr-active-sponsor-meta" data-active-sponsor-name>
              {@first_sponsor.name}
            </span>
          </div>

          <ul hidden aria-hidden="true">
            <li
              :for={sponsor <- @sponsor}
              data-collab-sponsor
              data-sponsor-name={sponsor.name}
              data-sponsor-role={sponsor.role}
              data-sponsor-logo={sponsor.logo}
              data-sponsor-dark={to_string(Map.get(sponsor, :dark, false))}
              data-sponsor-kind={Map.get(sponsor, :kind, "sponsor")}
            >
              <img src={sponsor.logo} alt="" />
            </li>
          </ul>
        </div>

        <div class="cr-right">
          <aside class="cr-join" aria-labelledby={"#{@id}-join-heading"}>
            <div class="cr-join__kicker">Scan to join</div>
            <h2 id={"#{@id}-join-heading"}>Join the room</h2>
            <p class="cr-join__copy">
              Ask questions, vote live, and take part from your phone.
            </p>

            <div class="cr-qr-frame">
              <div class="cr-qr">
                {render_slot(@qr)}
              </div>
            </div>

            <div class="cr-join__code">
              <p>Or go to {@join_url}</p>
              <strong>{@join_code}</strong>
            </div>

            <p class="cr-join__note">No app required. Open it in your browser.</p>
          </aside>
        </div>

        <footer class="cr-footer">
          <span>{@footer_left}</span>
          <span>{@footer_right}</span>
        </footer>
      </div>
    </div>
    """
  end
end

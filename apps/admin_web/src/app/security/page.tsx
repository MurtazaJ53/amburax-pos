import { AdminShell } from "@/components/admin-shell";
import { EmptyState } from "@/components/empty-state";
import { PasskeyControlPanel } from "@/components/passkey-control-panel";
import {
  beginMfaEnrollmentAction,
  disableMfaAction,
  verifyMfaCodeAction,
} from "@/app/security/actions";
import {
  getSession,
  getUserMfaStatus,
  getUserPasskeys,
  resolveActiveShop,
} from "@/lib/admin-api";
import { getAdminWebMfaPosture } from "@/lib/mfa";
import { canManageWorkspace } from "@/lib/roles";

type SearchParams = Record<string, string | string[] | undefined>;

type SecurityPageProps = {
  searchParams?: Promise<SearchParams>;
};

function getSearchParamValue(searchParams: SearchParams, key: string) {
  const raw = searchParams[key];
  return Array.isArray(raw) ? raw[0] : raw;
}

function buildBanner(searchParams: SearchParams) {
  const status = getSearchParamValue(searchParams, "status");
  const message = getSearchParamValue(searchParams, "message");

  if (!status) {
    return null;
  }

  if (status === "pending") {
    return {
      accent: "border-[var(--primary)]/30 bg-[var(--primary)]/10 text-[var(--primary-dark)]",
      title: "Setup started - one step left",
      body: "Scan the QR code below with your authenticator app, then type the six-digit code it shows to finish.",
    };
  }

  if (status === "enabled") {
    return {
      accent: "border-[var(--success)]/35 bg-[var(--success)]/10 text-[var(--success-dark)]",
      title: "Two-step sign-in is on",
      body: "From now on you will be asked for a code from your phone as well as your password.",
    };
  }

  if (status === "verified") {
    return {
      accent: "border-[var(--success)]/35 bg-[var(--success)]/10 text-[var(--success-dark)]",
      title: "Code accepted",
      body: "The owner-only screens are open again for a while. You will be asked again later.",
    };
  }

  if (status === "disabled") {
    return {
      accent: "border-[var(--warning)]/35 bg-[var(--warning)]/10 text-[var(--warning-strong)]",
      title: "Two-step sign-in is off",
      body: "Your password is now the only thing protecting this account. Turn it back on when you have a new phone set up.",
    };
  }

  return {
    accent: "border-[var(--error)]/35 bg-[var(--error)]/10 text-[var(--error-strong)]",
    title: "That did not go through",
    body: message || "Nothing was changed. Try again, and check the code has not expired.",
  };
}

export default async function SecurityPage({ searchParams }: SecurityPageProps) {
  const resolvedSearchParams = (await searchParams) ?? {};
  const session = await getSession();
  const activeShop = resolveActiveShop(session);
  const canUseSecurity =
    session.user.is_platform_admin || canManageWorkspace(activeShop?.role ?? null);
  const mfaStatus = canUseSecurity ? await getUserMfaStatus() : null;
  const passkeys = canUseSecurity ? await getUserPasskeys() : [];
  const mfaPosture = canUseSecurity
    ? await getAdminWebMfaPosture(session.user, true)
    : { required: false, enabled: false, verified: false };
  const banner = buildBanner(resolvedSearchParams);
  const returnTo = getSearchParamValue(resolvedSearchParams, "returnTo") ?? "";

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="security"
      title="Security"
      subtitle="Ask for a code from your phone as well as a password, before anyone opens the owner-only screens"
    >
      {!canUseSecurity || !mfaStatus ? (
        <EmptyState
          title="Only the owner and admins can change this"
          body="Two-step sign-in protects the screens that hold money, staff and plan settings. Ask the shop owner if you need it changed."
        />
      ) : (
        <div className="flex flex-col gap-4">
          {banner ? (
            <section className={`animate-fade-in-up rounded-[16px] border px-5 py-4 ${banner.accent}`}>
              <h2 className="m-0 text-base font-extrabold tracking-tight">{banner.title}</h2>
              <p className="m-0 mt-1.5 text-[13px] font-medium leading-[1.55] text-[var(--text-secondary)]">
                {banner.body}
              </p>
            </section>
          ) : null}

          {/* What this screen is, in the words of the person reading it. The
              page opened straight into "MFA posture" and "verified window",
              which tells a shopkeeper nothing about what it does or why they
              should care. */}
          <section className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm animate-fade-in-up">
            <h2 className="m-0 text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
              What this is
            </h2>
            <p className="m-0 mt-2 max-w-[70ch] text-[13px] font-medium leading-[1.6] text-[var(--text-secondary)]">
              Normally your password is the only thing standing between someone
              and your shop&apos;s money, staff and settings. Two-step sign-in
              adds a second thing: a six-digit code that changes every minute
              on your own phone. Someone who steals your password still cannot
              get in, because they do not have your phone.
            </p>
            <ul className="m-0 mt-3 flex list-none flex-col gap-1.5 p-0 text-[12.5px] font-medium text-[var(--text-secondary)]">
              <li className="flex gap-2">
                <span aria-hidden="true" className="text-[var(--text-tertiary)]">1.</span>
                Install an authenticator app on your phone - Google Authenticator
                or Microsoft Authenticator both work, and both are free.
              </li>
              <li className="flex gap-2">
                <span aria-hidden="true" className="text-[var(--text-tertiary)]">2.</span>
                Start setup below and scan the QR code with it.
              </li>
              <li className="flex gap-2">
                <span aria-hidden="true" className="text-[var(--text-tertiary)]">3.</span>
                Type the six digits it shows. That is it - you are done.
              </li>
            </ul>
            <p className="m-0 mt-3 text-[12px] font-semibold text-[var(--warning-strong)]">
              Keep the phone. If you lose it with no second way in, an owner can
              be locked out of their own shop.
            </p>
          </section>

          {/* One row, in plain words, replacing four cards of jargon. */}
          <section className="flex flex-wrap items-center gap-4 rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2.5 shadow-sm animate-fade-in-up">
            <dl className="no-scrollbar m-0 flex min-w-0 flex-1 items-stretch gap-4 overflow-x-auto">
              {[
                {
                  label: "two-step sign-in",
                  value:
                    mfaStatus.totp_enabled || mfaStatus.passkey_enabled
                      ? "On"
                      : mfaStatus.totp_pending_enrollment
                        ? "Half set up"
                        : "Off",
                  detail:
                    mfaStatus.totp_enabled || mfaStatus.passkey_enabled
                      ? "a code is asked for at sign-in"
                      : mfaStatus.totp_pending_enrollment
                        ? "finish it below"
                        : "password only",
                  tone:
                    mfaStatus.totp_enabled || mfaStatus.passkey_enabled
                      ? "text-[var(--success-strong)]"
                      : "text-[var(--warning-strong)]",
                },
                {
                  label: "owner screens",
                  value: mfaPosture.verified ? "Open" : "Locked",
                  detail: mfaPosture.verified
                    ? "you entered a code recently"
                    : "enter a code to open them",
                  tone: mfaPosture.verified
                    ? "text-[var(--success-strong)]"
                    : "text-[var(--text-primary)]",
                },
                {
                  label: "phones registered",
                  value: String(mfaStatus.passkey_count),
                  detail:
                    mfaStatus.passkey_count > 0 ? "can sign you in" : "none yet",
                  tone: "text-[var(--text-primary)]",
                },
                {
                  label: "asks again after",
                  value: `${Math.round(mfaStatus.challenge_window_seconds / 3600)}h`,
                  detail: "then you type a code again",
                  tone: "text-[var(--text-primary)]",
                },
              ].map((stat, index) => (
                <div
                  key={stat.label}
                  className={`flex shrink-0 flex-col justify-center ${
                    index > 0 ? "border-l border-[var(--border-soft)] pl-4" : ""
                  }`}
                >
                  <dt className="font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                    {stat.label}
                  </dt>
                  <dd className="m-0 flex items-baseline gap-1.5">
                    <span className={`tnum font-mono text-[17px] font-bold leading-tight ${stat.tone}`}>
                      {stat.value}
                    </span>
                    <span className="whitespace-nowrap text-[11px] font-semibold text-[var(--text-tertiary)]">
                      {stat.detail}
                    </span>
                  </dd>
                </div>
              ))}
            </dl>
          </section>

          <section className="grid items-start gap-4 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
            <div className="flex flex-col gap-4">
              {!mfaStatus.totp_enabled ? (
                <section className="animate-fade-in-up rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm">
                  <p className="m-0 font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">Step 1</p>
                  <h2 className="mt-2 text-sm font-extrabold tracking-tight text-[var(--text-primary)]">Turn on two-step sign-in</h2>
                  <p className="m-0 mt-1.5 max-w-[70ch] text-[13px] font-medium leading-[1.55] text-[var(--text-secondary)]">
                    Open your authenticator app, scan the code below, then type
                    the six digits it shows you. It takes about a minute.
                  </p>
                  {!mfaStatus.totp_pending_enrollment ? (
                    <form action={beginMfaEnrollmentAction} className="mt-4">
                      <input type="hidden" name="returnTo" value={returnTo} />
                      <button
                        type="submit"
                        className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-4 py-2.5 text-[12.5px] font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20"
                      >
                        Start MFA setup
                      </button>
                    </form>
                  ) : (
                    <div className="mt-4 flex flex-col gap-3">
                      <div className="rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-4">
                        <p className="m-0 font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">Manual secret</p>
                        <p className="m-0 mt-2 break-all font-mono text-[12.5px] font-semibold text-[var(--text-primary)]">
                          {mfaStatus.pending_manual_secret}
                        </p>
                      </div>
                      <div className="rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-4">
                        <p className="m-0 font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">Authenticator link</p>
                        <p className="m-0 mt-2 break-all text-[12px] font-medium text-[var(--text-secondary)]">
                          {mfaStatus.pending_otpauth_uri}
                        </p>
                      </div>
                      <form action={verifyMfaCodeAction} className="rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-4">
                        <input type="hidden" name="purpose" value="enroll" />
                        <input type="hidden" name="returnTo" value={returnTo} />
                        <label className="block">
                          <span className="block font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">Code from your phone</span>
                          <input
                            name="code"
                            inputMode="numeric"
                            maxLength={6}
                            placeholder="123456"
                            className="tnum mt-2 w-full max-w-[220px] rounded-[10px] border border-[var(--border-soft)] bg-[var(--bg-soft)] px-4 py-2.5 font-mono text-[19px] font-bold tracking-[0.22em] text-[var(--text-primary)] outline-none transition-colors placeholder:tracking-[0.22em] placeholder:text-[var(--text-tertiary)] focus:border-[var(--primary)]"
                          />
                        </label>
                        <button
                          type="submit"
                          className="focus-ring mt-4 inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--success)]/30 bg-[var(--success)]/12 px-4 py-2.5 text-[12.5px] font-extrabold text-[var(--success-dark)] transition-colors hover:bg-[var(--success)]/20"
                        >
                          Finish setup
                        </button>
                      </form>
                    </div>
                  )}
                </section>
              ) : (
                <section className="animate-fade-in-up rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm">
                  <p className="m-0 font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">Step 1</p>
                  <h2 className="mt-2 text-sm font-extrabold tracking-tight text-[var(--text-primary)]">Enter a code to open the owner screens</h2>
                  <p className="m-0 mt-1.5 max-w-[70ch] text-[13px] font-medium leading-[1.55] text-[var(--text-secondary)]">
                    Open your authenticator app and type the six digits it is
                    showing right now. They change every minute.
                  </p>
                  <form action={verifyMfaCodeAction} className="mt-4 rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-4">
                    <input type="hidden" name="purpose" value="challenge" />
                    <input type="hidden" name="returnTo" value={returnTo} />
                    <label className="block">
                      <span className="block font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">Code from your phone</span>
                      <input
                        name="code"
                        inputMode="numeric"
                        maxLength={6}
                        placeholder="123456"
                        className="tnum mt-2 w-full max-w-[220px] rounded-[10px] border border-[var(--border-soft)] bg-[var(--bg-soft)] px-4 py-2.5 font-mono text-[19px] font-bold tracking-[0.22em] text-[var(--text-primary)] outline-none transition-colors placeholder:tracking-[0.22em] placeholder:text-[var(--text-tertiary)] focus:border-[var(--primary)]"
                      />
                    </label>
                    <button
                      type="submit"
                      className="focus-ring mt-4 inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--success)]/30 bg-[var(--success)]/12 px-4 py-2.5 text-[12.5px] font-extrabold text-[var(--success-dark)] transition-colors hover:bg-[var(--success)]/20"
                    >
                      Open the owner screens
                    </button>
                  </form>
                </section>
              )}

              {mfaStatus.totp_enabled ? (
                <section className="animate-fade-in-up rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm">
                  <p className="m-0 font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">Step 2</p>
                  <h2 className="mt-2 text-sm font-extrabold tracking-tight text-[var(--text-primary)]">Turn it off</h2>
                  <p className="m-0 mt-1.5 max-w-[70ch] text-[13px] font-medium leading-[1.55] text-[var(--text-secondary)]">
                    Only do this if you are moving to a new phone. Your
                    password becomes the only lock on the shop again, and you
                    will have to set this up from scratch to turn it back on.
                  </p>
                  <form action={disableMfaAction} className="mt-4 rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-4">
                    <label className="block">
                      <span className="block font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">Code from your phone</span>
                      <input
                        name="code"
                        inputMode="numeric"
                        maxLength={6}
                        placeholder="123456"
                        className="tnum mt-2 w-full max-w-[220px] rounded-[10px] border border-[var(--border-soft)] bg-[var(--bg-soft)] px-4 py-2.5 font-mono text-[19px] font-bold tracking-[0.22em] text-[var(--text-primary)] outline-none transition-colors placeholder:tracking-[0.22em] placeholder:text-[var(--text-tertiary)] focus:border-[var(--primary)]"
                      />
                    </label>
                    <button
                      type="submit"
                      className="focus-ring mt-4 inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--error)]/35 bg-[var(--error)]/10 px-4 py-2.5 text-[12.5px] font-extrabold text-[var(--error-strong)] transition-colors hover:bg-[var(--error)]/18"
                    >
                      Turn off two-step sign-in
                    </button>
                  </form>
                </section>
              ) : null}

              <PasskeyControlPanel
                initialPasskeys={passkeys}
                returnTo={returnTo}
              />
            </div>

            <div className="flex flex-col gap-4">
              <section className="animate-fade-in-up rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm">
                <p className="m-0 font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                  What it guards
                </p>
                <h2 className="mt-2 text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
                  The screens a code is asked for
                </h2>
                <ul className="m-0 mt-3 flex list-none flex-col gap-2 p-0 text-[12.5px] font-medium text-[var(--text-secondary)]">
                  {[
                    "Your plan and anything that charges money",
                    "Adding staff, changing roles, handing over the shop",
                    "Signing a lost phone out, or wiping it",
                    "The audit trail of who did what",
                    "Payments the owner can see",
                    "The internal migration and ERPNext tools",
                  ].map((line) => (
                    <li key={line} className="flex gap-2">
                      <span aria-hidden="true" className="text-[var(--text-tertiary)]">
                        &middot;
                      </span>
                      {line}
                    </li>
                  ))}
                </ul>
              </section>

              <section className="animate-fade-in-up rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm">
                <p className="m-0 font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                  Your account
                </p>
                <h2 className="mt-2 text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
                  Where things stand
                </h2>
                {/* Label left, value right, on one baseline with a hairline
                    between. Four bordered boxes stacked down a narrow column
                    left every value starting at a different place and the
                    panel bottom ragged against the one beside it. */}
                <dl className="m-0 mt-3 flex flex-col">
                  {[
                    {
                      label: "Turned on",
                      value: mfaStatus.enabled_at || "Not yet",
                    },
                    {
                      label: "Code last entered",
                      value: mfaStatus.last_verified_at || "Never",
                    },
                    {
                      label: "Owner screens",
                      value: mfaPosture.verified ? "Open right now" : "Need a code",
                    },
                    {
                      label: "Phone last used",
                      value: mfaStatus.passkey_last_verified_at || "Never",
                    },
                  ].map((row) => (
                    <div
                      key={row.label}
                      className="flex items-baseline justify-between gap-4 border-b border-[var(--border-soft)] py-2.5 last:border-b-0"
                    >
                      <dt className="shrink-0 text-[12px] font-semibold text-[var(--text-tertiary)]">
                        {row.label}
                      </dt>
                      <dd className="tnum m-0 min-w-0 truncate text-right text-[12.5px] font-bold text-[var(--text-primary)]">
                        {row.value}
                      </dd>
                    </div>
                  ))}
                </dl>
              </section>
            </div>
          </section>
        </div>
      )}
    </AdminShell>
  );
}

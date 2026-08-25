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
        <div className="space-y-8">
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

          <section className="grid gap-6 xl:grid-cols-[minmax(0,1.12fr)_minmax(0,0.88fr)]">
            <div className="space-y-6">
              {!mfaStatus.totp_enabled ? (
                <section className="panel-soft rounded-[28px] px-6 py-6">
                  <p className="eyebrow">Step 1</p>
                  <h2 className="mt-3 text-2xl font-bold">Turn on two-step sign-in</h2>
                  <p className="mt-2 text-sm text-[var(--text-secondary)]">
                    Open your authenticator app, scan the code below, then type
                    the six digits it shows you. It takes about a minute.
                  </p>
                  {!mfaStatus.totp_pending_enrollment ? (
                    <form action={beginMfaEnrollmentAction} className="mt-6">
                      <input type="hidden" name="returnTo" value={returnTo} />
                      <button
                        type="submit"
                        className="inline-flex rounded-full border border-[rgba(92,174,254,0.22)] bg-[rgba(10,36,68,0.82)] px-5 py-2.5 text-sm font-semibold text-[var(--accent)] transition-transform duration-150 hover:-translate-y-0.5"
                      >
                        Start MFA setup
                      </button>
                    </form>
                  ) : (
                    <div className="mt-6 space-y-4">
                      <div className="surface-muted rounded-[22px] px-5 py-5">
                        <p className="eyebrow">Manual secret</p>
                        <p className="mt-3 break-all font-mono text-sm text-[var(--text-primary)]">
                          {mfaStatus.pending_manual_secret}
                        </p>
                      </div>
                      <div className="surface-muted rounded-[22px] px-5 py-5">
                        <p className="eyebrow">Authenticator link</p>
                        <p className="mt-3 break-all text-sm text-[var(--text-secondary)]">
                          {mfaStatus.pending_otpauth_uri}
                        </p>
                      </div>
                      <form action={verifyMfaCodeAction} className="surface-muted rounded-[22px] px-5 py-5">
                        <input type="hidden" name="purpose" value="enroll" />
                        <input type="hidden" name="returnTo" value={returnTo} />
                        <label className="block">
                          <span className="eyebrow">Verification code</span>
                          <input
                            name="code"
                            inputMode="numeric"
                            maxLength={6}
                            placeholder="123456"
                            className="mt-3 w-full rounded-[18px] border border-[rgba(152,164,189,0.14)] bg-[rgba(8,14,24,0.72)] px-4 py-3 text-sm text-[var(--text-primary)] outline-none placeholder:text-[var(--text-muted)]"
                          />
                        </label>
                        <button
                          type="submit"
                          className="mt-4 inline-flex rounded-full border border-[rgba(58,215,162,0.18)] bg-[rgba(9,42,31,0.64)] px-5 py-2.5 text-sm font-semibold text-[var(--success)] transition-transform duration-150 hover:-translate-y-0.5"
                        >
                          Verify and enable MFA
                        </button>
                      </form>
                    </div>
                  )}
                </section>
              ) : (
                <section className="panel-soft rounded-[28px] px-6 py-6">
                  <p className="eyebrow">Step 1</p>
                  <h2 className="mt-3 text-2xl font-bold">Refresh your secure access window</h2>
                  <p className="mt-2 text-sm text-[var(--text-secondary)]">
                    Verify one current MFA code before opening protected owner/admin surfaces like Workspace plan, Team,
                    Sessions, Audit, Migration, and ERPNext control.
                  </p>
                  <form action={verifyMfaCodeAction} className="mt-6 surface-muted rounded-[22px] px-5 py-5">
                    <input type="hidden" name="purpose" value="challenge" />
                    <input type="hidden" name="returnTo" value={returnTo} />
                    <label className="block">
                      <span className="eyebrow">Verification code</span>
                      <input
                        name="code"
                        inputMode="numeric"
                        maxLength={6}
                        placeholder="123456"
                        className="mt-3 w-full rounded-[18px] border border-[rgba(152,164,189,0.14)] bg-[rgba(8,14,24,0.72)] px-4 py-3 text-sm text-[var(--text-primary)] outline-none placeholder:text-[var(--text-muted)]"
                      />
                    </label>
                    <button
                      type="submit"
                      className="mt-4 inline-flex rounded-full border border-[rgba(58,215,162,0.18)] bg-[rgba(9,42,31,0.64)] px-5 py-2.5 text-sm font-semibold text-[var(--success)] transition-transform duration-150 hover:-translate-y-0.5"
                    >
                      Verify now
                    </button>
                  </form>
                </section>
              )}

              {mfaStatus.totp_enabled ? (
                <section className="panel-soft rounded-[28px] px-6 py-6">
                  <p className="eyebrow">Step 2</p>
                  <h2 className="mt-3 text-2xl font-bold">Disable MFA only if you are replacing the authenticator</h2>
                  <p className="mt-2 text-sm text-[var(--text-secondary)]">
                    Disabling MFA immediately closes the current secure-access window and forces a new setup before
                    protected owner/admin surfaces can reopen.
                  </p>
                  <form action={disableMfaAction} className="mt-6 surface-muted rounded-[22px] px-5 py-5">
                    <label className="block">
                      <span className="eyebrow">Current code</span>
                      <input
                        name="code"
                        inputMode="numeric"
                        maxLength={6}
                        placeholder="123456"
                        className="mt-3 w-full rounded-[18px] border border-[rgba(152,164,189,0.14)] bg-[rgba(8,14,24,0.72)] px-4 py-3 text-sm text-[var(--text-primary)] outline-none placeholder:text-[var(--text-muted)]"
                      />
                    </label>
                    <button
                      type="submit"
                      className="mt-4 inline-flex rounded-full border border-[rgba(251,113,133,0.18)] bg-[rgba(40,12,19,0.76)] px-5 py-2.5 text-sm font-semibold text-[var(--warning)] transition-transform duration-150 hover:-translate-y-0.5"
                    >
                      Disable MFA
                    </button>
                  </form>
                </section>
              ) : null}

              <PasskeyControlPanel
                initialPasskeys={passkeys}
                returnTo={returnTo}
              />
            </div>

            <div className="space-y-6">
              <section className="panel-soft rounded-[28px] px-6 py-6">
                <p className="eyebrow">Protection map</p>
                <h2 className="mt-3 text-2xl font-bold">What MFA protects now</h2>
                <ul className="mt-4 space-y-3 text-sm leading-7 text-[var(--text-secondary)]">
                  <li>Workspace plan and upgrade controls</li>
                  <li>Team management and ownership transfer</li>
                  <li>Workspace session revoke / remote wipe</li>
                  <li>Audit trail review</li>
                  <li>Owner/admin payments review</li>
                  <li>Migration and ERPNext internal control pages</li>
                  <li>Matching owner/admin mobile security gates</li>
                </ul>
              </section>

              <section className="panel-soft rounded-[28px] px-6 py-6">
                <p className="eyebrow">Current status</p>
                <h2 className="mt-3 text-2xl font-bold">How your account looks right now</h2>
                <div className="mt-5 space-y-4 text-sm text-[var(--text-secondary)]">
                  <div className="surface-muted rounded-[20px] px-4 py-4">
                    <p className="eyebrow">Enabled at</p>
                    <p className="mt-2 text-base font-semibold text-[var(--text-primary)]">
                      {mfaStatus.enabled_at || "Not enabled"}
                    </p>
                  </div>
                  <div className="surface-muted rounded-[20px] px-4 py-4">
                    <p className="eyebrow">Last verified</p>
                    <p className="mt-2 text-base font-semibold text-[var(--text-primary)]">
                      {mfaStatus.last_verified_at || "No successful challenge yet"}
                    </p>
                  </div>
                  <div className="surface-muted rounded-[20px] px-4 py-4">
                    <p className="eyebrow">Secure window</p>
                    <p className="mt-2 text-base font-semibold text-[var(--text-primary)]">
                      {mfaPosture.verified ? "Open right now" : "Needs verification"}
                    </p>
                  </div>
                  <div className="surface-muted rounded-[20px] px-4 py-4">
                    <p className="eyebrow">Last passkey verification</p>
                    <p className="mt-2 text-base font-semibold text-[var(--text-primary)]">
                      {mfaStatus.passkey_last_verified_at || "No passkey verification yet"}
                    </p>
                  </div>
                </div>
              </section>
            </div>
          </section>
        </div>
      )}
    </AdminShell>
  );
}

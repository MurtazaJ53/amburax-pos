"""Transactional email via Resend.

A thin, dependency-free wrapper over the Resend HTTP API (urllib only). It is
safe to call anywhere: if RESEND_API_KEY is not configured (local/dev/tests),
it logs and no-ops instead of failing, so email is never a hard dependency of a
request path.
"""
from __future__ import annotations

import json
import logging
import os
import time
import urllib.error
import urllib.request

logger = logging.getLogger(__name__)

_RESEND_ENDPOINT = "https://api.resend.com/emails"


def resend_api_key() -> str:
    """Public so configuration checks read exactly what the sender reads."""
    return os.getenv("RESEND_API_KEY", "").strip()


def resend_from_address() -> str:
    # Resend requires a verified sender; onboarding@resend.dev works out of the
    # box for testing before a domain is verified.
    return os.getenv("RESEND_FROM", "Business Hub <onboarding@resend.dev>")


_MAX_ATTEMPTS = 3


def send_email(*, to: str, subject: str, html: str, text: str = "") -> dict:
    """Send one email via Resend. Never raises.

    Returns a structured result so callers/admins can see what actually
    happened, instead of a misleading blanket "sent":
      {"ok": bool, "skipped": bool, "id": str, "error": str, "status": str}
    - skipped: no API key configured (dev/test)
    - ok: Resend accepted the message (has an id)
    - error/status: the provider's message on failure (e.g. test-mode recipient
      restriction) so it can be surfaced and logged.

    Transient failures (5xx / network) are retried with backoff; permanent 4xx
    failures (bad recipient, unverified domain) are not.
    """
    key = resend_api_key()
    if not key:
        logger.info("Email skipped (no RESEND_API_KEY): to=[REDACTED] subject=%s", subject)
        return {"ok": False, "skipped": True, "id": "", "error": "",
                "status": "skipped: RESEND_API_KEY not set"}

    payload = json.dumps(
        {
            "from": resend_from_address(),
            "to": [to],
            "subject": subject,
            "html": html,
            **({"text": text} if text else {}),
        }
    ).encode("utf-8")

    last_error = ""
    for attempt in range(1, _MAX_ATTEMPTS + 1):
        request = urllib.request.Request(
            _RESEND_ENDPOINT,
            data=payload,
            method="POST",
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
                # A real User-Agent is required: Resend sits behind Cloudflare,
                # which blocks urllib's default "Python-urllib/x" UA with a 1010
                # error, so requests never reach the API.
                "User-Agent": "BusinessHub/1.0 (+https://businesshub.pro)",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                raw = response.read().decode("utf-8", "replace")
                message_id = ""
                try:
                    message_id = (json.loads(raw) or {}).get("id", "")
                except Exception:
                    pass
                logger.info(
                    "Email sent to=[REDACTED] id=%s (attempt %d)", message_id, attempt
                )
                return {"ok": True, "skipped": False, "id": message_id,
                        "error": "", "status": "sent"}
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", "replace")
            detail = body
            try:
                detail = (json.loads(body) or {}).get("message", body)
            except Exception:
                pass
            last_error = f"{exc.code}: {detail}"[:400]
            logger.warning(
                "Resend HTTPError %s for to=[REDACTED] (attempt %d): %s",
                exc.code, attempt, detail,
            )
            # 4xx is permanent (bad recipient, unverified domain) - don't retry.
            if 400 <= exc.code < 500:
                return {"ok": False, "skipped": False, "id": "",
                        "error": last_error, "status": "failed"}
        except Exception as exc:
            last_error = str(exc)[:400]
            logger.warning(
                "Resend send failed for to=[REDACTED] (attempt %d): %s", attempt, exc
            )
        if attempt < _MAX_ATTEMPTS:
            time.sleep(0.5 * attempt)  # linear backoff

    return {"ok": False, "skipped": False, "id": "", "error": last_error,
            "status": "failed after retries"}


def send_invite_email(
    *, to: str, shop_name: str, role_label: str, invite_code: str, inviter: str = ""
) -> dict:
    """Compose and send a shop invitation email."""
    who = f"{inviter} invited you" if inviter else "You've been invited"
    subject = f"{who} to join {shop_name} on Business Hub"
    frontend_url = os.getenv("FRONTEND_URL", "http://localhost:3000")
    accept_link = f"{frontend_url}/invite/{invite_code}"

    html = f"""
    <div style="font-family:system-ui,Segoe UI,Arial,sans-serif;max-width:520px;margin:auto">
      <h2 style="color:#0d6e8c">Join {shop_name} on Business Hub</h2>
      <p>{who} as <b>{role_label}</b>.</p>
      <p>Open the Business Hub app, choose <b>“Join with invite code”</b>, and enter this code:</p>
      <p style="font-size:22px;font-weight:700;letter-spacing:2px;background:#e4f1f5;
                padding:12px 16px;border-radius:10px;display:inline-block">{invite_code}</p>
      <p>Or accept the invitation directly in your web browser by clicking here:</p>
      <p><a href="{accept_link}" style="display:inline-block;background:#0d6e8c;color:#fff;
                padding:10px 20px;text-decoration:none;border-radius:5px">Accept Invitation</a></p>
      <p style="color:#54617a;font-size:13px">This invite expires in 7 days. If you didn't expect it, you can ignore this email.</p>
    </div>
    """
    text = (
        f"{who} to join {shop_name} as {role_label} on Business Hub.\n"
        f'Open the app, choose "Join with invite code", and enter: {invite_code}\n'
        f"Or open this link in your browser: {accept_link}\n"
        f"This invite expires in 7 days."
    )
    return send_email(to=to, subject=subject, html=html, text=text)


def send_password_reset_email(*, to: str, reset_link: str, ttl_label: str) -> dict:
    """Compose and send a password reset link.

    Returns the same structured result as send_email, because the caller has
    to be able to tell a shop owner the truth about whether the message left
    the building.
    """
    subject = "Reset your Business Hub password"
    html = f"""
    <div style="font-family:system-ui,Segoe UI,Arial,sans-serif;max-width:520px;margin:auto">
      <h2 style="color:#0d6e8c">Reset your password</h2>
      <p>Somebody asked to reset the password for this Business Hub account.
         If that was you, choose a new password here:</p>
      <p><a href="{reset_link}" style="display:inline-block;background:#0d6e8c;color:#fff;
                padding:10px 20px;text-decoration:none;border-radius:5px">Choose a new password</a></p>
      <p style="color:#54617a;font-size:13px">Or paste this link into your browser:<br>
         <span style="word-break:break-all">{reset_link}</span></p>
      <p style="color:#54617a;font-size:13px">This link works once and expires in {ttl_label}.
         If you didn't ask for it, ignore this email — your password stays as it is.</p>
    </div>
    """
    text = (
        "Somebody asked to reset the password for this Business Hub account.\n"
        f"If that was you, open this link to choose a new password:\n{reset_link}\n"
        f"The link works once and expires in {ttl_label}.\n"
        "If you didn't ask for it, ignore this email - your password stays as it is."
    )
    return send_email(to=to, subject=subject, html=html, text=text)

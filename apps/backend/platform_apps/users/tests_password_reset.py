"""Does the forgot-password flow actually let a locked-out owner back in?

The manual path is pinned next door in tests_password_recovery.py, and it is
still there: an operator with a shell can always reset an account. What these
tests cover is the self-serve path a shopkeeper can walk on a Tuesday morning
without phoning anybody.

Four things have to hold, and each of them has been quietly wrong in some
product at some point:

  - The link expires, and a link that has been used is spent. A reset token
    that keeps working is a permanent spare key to somebody's shop.
  - Asking about an address that has no account gets the same answer as asking
    about one that does. Otherwise the form is a free membership check.
  - The password that comes out the far end is one the real sign-in endpoint
    accepts - not merely stored. A password that is saved but not accepted
    leaves the shop exactly as shut as before.
  - When mail does not go out, the reply says so. This codebase has spent weeks
    removing controls that look like they work; a 200 for an email that never
    left is the same bug in a new coat.
"""
from __future__ import annotations

from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.users.models import PasswordResetToken

User = get_user_model()

SENT = {"ok": True, "skipped": False, "id": "msg_1", "error": "", "status": "sent"}
NOT_SENT = {
    "ok": False,
    "skipped": False,
    "id": "",
    "error": "422: Invalid `to` field.",
    "status": "failed",
}


class PasswordResetFlowTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="locked.out@example.com",
            password="the-forgotten-one",
            full_name="Shop Owner",
        )
        self.client = APIClient()

    # -- helpers -------------------------------------------------------

    def _request_reset(self, email: str, send_result=SENT):
        """Ask for a link, with the mailer's answer under our control.

        Patched where it is used rather than where it is defined, so the test
        pins the view's own call site.
        """
        with patch(
            "platform_apps.users.password_reset_views.send_password_reset_email",
            return_value=send_result,
        ) as mailer:
            response = self.client.post(
                reverse("session-password-reset"), {"email": email}, format="json"
            )
        return response, mailer

    def _confirm(self, token: str, password: str):
        return self.client.post(
            reverse("session-password-reset-confirm"),
            {"token": token, "password": password},
            format="json",
        )

    def _sign_in(self, email: str, password: str):
        return self.client.post(
            reverse("session-token-obtain"),
            {"email": email, "password": password},
            format="json",
        )

    def _token_from_link(self, mailer) -> str:
        """The raw token as the recipient would read it out of the email."""
        link = mailer.call_args.kwargs["reset_link"]
        return link.split("token=", 1)[1]

    # -- the happy path ------------------------------------------------

    def test_the_owner_can_sign_in_with_the_password_they_chose(self):
        # The assertion the whole feature exists for.
        _, mailer = self._request_reset("locked.out@example.com")
        token = self._token_from_link(mailer)

        confirm = self._confirm(token, "a-new-password-1")
        self.assertEqual(confirm.status_code, 200, confirm.content)

        signin = self._sign_in("locked.out@example.com", "a-new-password-1")
        self.assertEqual(signin.status_code, 200, signin.content)
        self.assertTrue(signin.json().get("access"))

    def test_the_forgotten_password_stops_working(self):
        # Otherwise the reset is an addition rather than a replacement, and
        # whoever knew the old one still has the shop.
        _, mailer = self._request_reset("locked.out@example.com")
        self._confirm(self._token_from_link(mailer), "a-new-password-1")

        signin = self._sign_in("locked.out@example.com", "the-forgotten-one")
        self.assertNotEqual(signin.status_code, 200)

    def test_the_email_carries_a_link_and_the_database_carries_only_a_hash(self):
        _, mailer = self._request_reset("locked.out@example.com")
        raw_token = self._token_from_link(mailer)

        stored = PasswordResetToken.objects.get(user=self.user)
        self.assertNotEqual(stored.token_hash, raw_token)
        self.assertEqual(stored.token_hash, PasswordResetToken.hash_token(raw_token))
        # A dump of this table must not hand anybody a working link.
        self.assertNotIn(raw_token, str(stored.__dict__))

    # -- the ways a link stops working ---------------------------------

    def test_an_expired_token_is_refused(self):
        _, mailer = self._request_reset("locked.out@example.com")
        token = self._token_from_link(mailer)

        PasswordResetToken.objects.filter(user=self.user).update(
            expires_at=timezone.now() - timedelta(minutes=1)
        )

        confirm = self._confirm(token, "a-new-password-1")
        self.assertEqual(confirm.status_code, 400, confirm.content)
        # And it did not quietly change the password on the way out.
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("the-forgotten-one"))

    def test_a_used_token_cannot_be_used_again(self):
        # A forwarded email, a shared browser, a link sitting in an inbox for
        # a year: one use is all a reset link ever gets.
        _, mailer = self._request_reset("locked.out@example.com")
        token = self._token_from_link(mailer)
        self.assertEqual(self._confirm(token, "a-new-password-1").status_code, 200)

        second = self._confirm(token, "an-attackers-password-9")
        self.assertEqual(second.status_code, 400, second.content)

        # The password is still the one the owner chose, not the second one.
        signin = self._sign_in("locked.out@example.com", "a-new-password-1")
        self.assertEqual(signin.status_code, 200, signin.content)

    def test_asking_again_retires_the_previous_link(self):
        # "It didn't arrive, send another" must not leave two working keys.
        _, first_mailer = self._request_reset("locked.out@example.com")
        first_token = self._token_from_link(first_mailer)
        _, second_mailer = self._request_reset("locked.out@example.com")
        second_token = self._token_from_link(second_mailer)

        self.assertEqual(self._confirm(first_token, "a-new-password-1").status_code, 400)
        self.assertEqual(self._confirm(second_token, "a-new-password-1").status_code, 200)

    def test_a_made_up_token_is_refused(self):
        self.assertEqual(
            self._confirm("not-a-real-token", "a-new-password-1").status_code, 400
        )

    def test_a_reset_signs_out_sessions_issued_before_it(self):
        # If the reason for the reset is that somebody else got in, their
        # access token must stop working too.
        before = self._sign_in("locked.out@example.com", "the-forgotten-one")
        stale_access = before.json()["access"]
        _, mailer = self._request_reset("locked.out@example.com")
        self._confirm(self._token_from_link(mailer), "a-new-password-1")

        response = self.client.get(
            reverse("session-bootstrap"), HTTP_AUTHORIZATION=f"Bearer {stale_access}"
        )
        self.assertEqual(response.status_code, 401, response.content)

    # -- no user enumeration -------------------------------------------

    def test_an_unknown_email_still_returns_the_same_200(self):
        known, _ = self._request_reset("locked.out@example.com")
        unknown, mailer = self._request_reset("nobody@example.com")

        self.assertEqual(unknown.status_code, 200, unknown.content)
        # The whole body, not just the sentence. An extra field that differs -
        # an "email_sent" flag, say - is the same membership check wearing a
        # different hat, and this endpoint briefly had exactly that.
        self.assertEqual(unknown.json(), known.json())
        # And nothing was sent to an address with no account.
        mailer.assert_not_called()
        self.assertEqual(PasswordResetToken.objects.count(), 1)

    def test_no_token_is_ever_shown_to_the_person_asking(self):
        # Showing the token on screen would turn the reset form into a
        # one-click takeover of any address a stranger can type.
        response, mailer = self._request_reset("locked.out@example.com")
        body = response.content.decode()
        self.assertNotIn(self._token_from_link(mailer), body)
        stored = PasswordResetToken.objects.get(user=self.user)
        self.assertNotIn(stored.token_hash, body)

    def test_an_inactive_account_is_treated_like_an_unknown_one(self):
        self.user.is_active = False
        self.user.save(update_fields=["is_active"])

        response, mailer = self._request_reset("locked.out@example.com")
        self.assertEqual(response.status_code, 200)
        mailer.assert_not_called()

    # -- honesty about delivery ----------------------------------------

    def test_a_send_that_failed_says_so_rather_than_reporting_success(self):
        # The live failure today is Resend's 422 for an unverified domain.
        # Whatever the cause, the person must not be told to watch an inbox
        # that will never receive anything.
        response, _ = self._request_reset("locked.out@example.com", send_result=NOT_SENT)

        self.assertEqual(response.status_code, 502, response.content)
        self.assertFalse(response.json()["email_sent"])
        self.assertIn("nothing has been sent", response.json()["detail"])

    def test_a_link_that_was_never_delivered_is_not_left_usable(self):
        _, mailer = self._request_reset("locked.out@example.com", send_result=NOT_SENT)
        token = self._token_from_link(mailer)

        self.assertEqual(self._confirm(token, "a-new-password-1").status_code, 400)

    def test_the_delivery_outcome_is_recorded_for_the_operator(self):
        self._request_reset("locked.out@example.com", send_result=NOT_SENT)
        self.assertEqual(PasswordResetToken.objects.get().delivery_status, "failed")

    # -- what the new password has to survive --------------------------

    def test_a_password_the_validators_reject_is_refused(self):
        _, mailer = self._request_reset("locked.out@example.com")
        token = self._token_from_link(mailer)

        response = self._confirm(token, "password")
        self.assertEqual(response.status_code, 400, response.content)
        # And the link survives, so the owner gets another go at choosing.
        self.assertEqual(self._confirm(token, "a-new-password-1").status_code, 200)

    def test_a_short_password_is_refused(self):
        _, mailer = self._request_reset("locked.out@example.com")
        response = self._confirm(self._token_from_link(mailer), "short")
        self.assertEqual(response.status_code, 400, response.content)

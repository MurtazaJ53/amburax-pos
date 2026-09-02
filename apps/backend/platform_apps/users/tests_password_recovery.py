"""Can a locked-out shop owner be let back in by an operator?

There is now a self-serve password reset as well — a "forgot password" link,
a request endpoint, an expiring single-use token, and mail out through Resend.
It is covered next door in tests_password_reset.py.

This file keeps covering the other path: an operator with a shell. It is not a
leftover. Mail can fail (the domain has to be verified before Resend will send
anywhere), a person can lose access to the inbox itself, and the reset link is
no use to either. When that happens the management command is the only way
back in, so it stays pinned: an owner who forgets their password on a Tuesday
morning cannot open their own till, and "we think there is a management
command" is not an answer to give somebody whose shop is shut.

Two things have to hold. The command must find the account by email, since
this project replaced username with email and Django's own command resolves
by whatever USERNAME_FIELD says. And the password it sets must be the one the
real sign-in endpoint accepts — not merely stored, but accepted.
"""
from __future__ import annotations

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

User = get_user_model()


class OperatorPasswordRecoveryTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="locked.out@example.com",
            password="the-forgotten-one",
            full_name="Shop Owner",
        )
        self.client = APIClient()

    def _reset_to(self, email: str, password: str) -> None:
        """What the operator types, minus the interactive prompt.

        changepassword reads the new password from a tty, which a test does
        not have. Everything else - how the account is looked up, how the
        password is hashed and saved - runs exactly as it does on the server.
        """
        from django.contrib.auth.management.commands import changepassword

        command = changepassword.Command()
        command._get_pass = lambda *args, **kwargs: password  # type: ignore[method-assign]
        call_command(command, email)

    def _sign_in(self, email: str, password: str):
        return self.client.post(
            reverse("session-token-obtain"),
            {"email": email, "password": password},
            format="json",
        )

    def test_the_account_is_found_by_email(self):
        # This project logs in with an email and has no usernames at all. If
        # the command resolved by username it would report "user does not
        # exist" for an account that plainly does, and the operator would go
        # looking for a database problem that was not there.
        self._reset_to("locked.out@example.com", "a-new-password-1")

        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("a-new-password-1"))

    def test_the_owner_can_sign_in_with_the_new_password(self):
        # The assertion that matters. A password that is stored but not
        # accepted leaves the shop exactly as shut as before.
        self._reset_to("locked.out@example.com", "a-new-password-1")

        response = self._sign_in("locked.out@example.com", "a-new-password-1")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertTrue(response.json().get("access"))

    def test_the_forgotten_password_stops_working(self):
        # Otherwise the reset is an addition rather than a replacement, and
        # whoever knew the old one still has the shop.
        self._reset_to("locked.out@example.com", "a-new-password-1")

        response = self._sign_in("locked.out@example.com", "the-forgotten-one")
        self.assertNotEqual(response.status_code, 200)

    def test_an_unknown_email_is_refused_rather_than_guessed_at(self):
        with self.assertRaises(CommandError):
            self._reset_to("nobody@example.com", "a-new-password-1")

    def test_the_self_service_reset_endpoint_exists_alongside_this_one(self):
        # This used to assert 404 on both, pinning the gap. The gap is closed:
        # /session/password-reset/ is live (see tests_password_reset.py), so
        # what is pinned here is that the operator path did not get replaced
        # by it. A bare POST with no email is a validation error, not a 404 -
        # that difference is the whole point of the assertion.
        response = self.client.post("/api/v1/session/password-reset/", {}, format="json")
        self.assertEqual(response.status_code, 400, response.content)

        # And nothing answers a route that was never built.
        self.assertEqual(
            self.client.post("/api/v1/session/forgot-password/", {}, format="json").status_code,
            404,
        )

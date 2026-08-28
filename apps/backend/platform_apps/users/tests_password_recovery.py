"""Can a locked-out shop owner be let back in?

There is no password reset in this product. No "forgot password" link, no
reset endpoint, no token — and on a deployment with no mail server there
would be nothing to send one with anyway. That is a real gap, and it is
written down in FUTURE.md rather than papered over here.

What exists instead is an operator with a shell. These tests pin that path
down, because it is the only one a locked-out client has and nobody had ever
run it: an owner who forgets their password on a Tuesday morning cannot open
their own till, and "we think there is a management command" is not an answer
to give somebody whose shop is shut.

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

    def test_no_self_service_reset_endpoint_is_advertised(self):
        # Pinning the gap deliberately. If somebody adds a reset route later,
        # this test fails and sends them here to delete the note in FUTURE.md
        # and the operator-only wording that goes with it.
        for path in ("/api/v1/session/password-reset/", "/api/v1/session/forgot-password/"):
            self.assertEqual(self.client.post(path, {}, format="json").status_code, 404)

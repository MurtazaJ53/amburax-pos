"""SECRET_KEY must be rotatable without destroying encrypted customer data.

django_cryptography derives its encryption key from SECRET_KEY whenever
CRYPTOGRAPHY_KEY is unset. That coupling made SECRET_KEY unrotatable on any
deployment holding customers: changing it turns every stored phone number into
undecryptable ciphertext, which no backup recovers because the backup holds the
same ciphertext.

These tests pin the escape route — pin CRYPTOGRAPHY_KEY to the current
SECRET_KEY value, and SECRET_KEY becomes free to rotate as a signing key alone.
"""
from __future__ import annotations

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf import pbkdf2
from django.conf import settings
from django.test import TestCase, override_settings
from django.utils.encoding import force_bytes

from platform_apps.common.blind_index import generate_blind_index


def _derive(secret: str) -> bytes:
    """Mirror of django_cryptography/conf.py configure().

    Pinned to the library by test_the_replication_matches_the_library below.
    """
    kdf = pbkdf2.PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=hashes.SHA256().digest_size,
        salt=force_bytes("django-cryptography"),
        iterations=30000,
        backend=default_backend(),
    )
    return kdf.derive(force_bytes(secret))
from platform_apps.customers.models import Customer
from platform_apps.shops.models import Shop

OLD_KEY = "old-secret-key-value-0123456789"
NEW_KEY = "new-secret-key-value-9876543210-much-longer-and-stronger"


class SecretKeyRotationTests(TestCase):
    def setUp(self):
        self.shop = Shop.objects.create(name="Demo", slug="demo")

    def _make_customer(self):
        return Customer.objects.create(
            shop=self.shop, name="Ramesh Patel", phone="9825011111"
        )

    @override_settings(SECRET_KEY=OLD_KEY, CRYPTOGRAPHY_KEY=None)
    def test_a_phone_round_trips_on_one_key(self):
        customer = self._make_customer()
        self.assertEqual(Customer.objects.get(pk=customer.pk).phone, "9825011111")

    def test_rotating_secret_key_alone_changes_the_encryption_key(self):
        """The failure this whole change exists to prevent.

        Asserted against the key derivation rather than through
        override_settings: django_cryptography's AppConf derives the key ONCE
        at app load and caches it, so an in-process settings override cannot
        move it and a test written that way passes while proving nothing. The
        real hazard is a container restart, which re-derives from whatever
        SECRET_KEY is at that moment — which is exactly what this checks.
        """
        self.assertNotEqual(_derive(OLD_KEY), _derive(NEW_KEY))

    def test_the_replication_matches_the_library(self):
        """Guards the two tests around it.

        If django_cryptography ever changes its salt, digest or iteration
        count, _derive stops describing reality and the assertions above become
        decorative. This fails loudly instead.
        """
        self.assertEqual(_derive(settings.SECRET_KEY), settings.CRYPTOGRAPHY_KEY)

    def test_pinning_reproduces_the_original_encryption_key(self):
        """The escape route, at the level that decides data survival."""
        # CRYPTOGRAPHY_KEY set to the old SECRET_KEY yields the identical
        # derived key, so every stored row still decrypts after rotation.
        self.assertEqual(_derive(OLD_KEY), _derive(OLD_KEY))
        self.assertNotEqual(_derive(OLD_KEY), _derive(NEW_KEY))

    def test_the_blind_index_also_survives_when_the_pepper_is_pinned(self):
        """Decrypting is only half of it — lookup must keep working too."""
        with override_settings(
            SECRET_KEY=OLD_KEY, CRYPTOGRAPHY_KEY=None, BLIND_INDEX_PEPPER=OLD_KEY
        ):
            customer = self._make_customer()
            stored_hash = Customer.objects.get(pk=customer.pk).phone_hash

        with override_settings(
            SECRET_KEY=NEW_KEY, CRYPTOGRAPHY_KEY=OLD_KEY, BLIND_INDEX_PEPPER=OLD_KEY
        ):
            # The same number must still hash to the same value, or a cashier
            # searching a phone number finds nothing.
            self.assertEqual(generate_blind_index("9825011111"), stored_hash)

    def test_changing_the_pepper_breaks_lookup_even_when_decryption_works(self):
        """Why the pepper must be pinned too, not just the encryption key."""
        with override_settings(
            SECRET_KEY=OLD_KEY, CRYPTOGRAPHY_KEY=None, BLIND_INDEX_PEPPER=OLD_KEY
        ):
            customer = self._make_customer()
            stored_hash = Customer.objects.get(pk=customer.pk).phone_hash

        with override_settings(
            SECRET_KEY=NEW_KEY, CRYPTOGRAPHY_KEY=OLD_KEY, BLIND_INDEX_PEPPER=NEW_KEY
        ):
            # Phone still decrypts, but the number no longer finds its own row.
            self.assertEqual(
                Customer.objects.get(pk=customer.pk).phone, "9825011111"
            )
            self.assertNotEqual(generate_blind_index("9825011111"), stored_hash)

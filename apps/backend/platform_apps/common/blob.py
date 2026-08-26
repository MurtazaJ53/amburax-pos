"""Where a stored file actually lives.

Product photos were base64 text in a column on the product. That put them in
the same table the till reads to ring up a sale, so they travelled with every
backup, every replica and every query that touched the row. This is the layer
that moves them out without the rest of the app knowing or caring.

Two backends, one interface, chosen by configuration. Disk is the default
because it needs no vendor, no account and no new dependency; S3 covers
DigitalOcean Spaces, Cloudflare R2 and AWS alike, since all three speak the
same protocol and differ only by endpoint. Switching is an environment
variable, not a rewrite.

Keys are the content's own hash, and that decision carries three consequences
worth stating.

Two products with the same photo store one copy. A shop photographing a shelf
of near-identical items pays for one.

A changed photo is a different key, so nothing has to be invalidated anywhere
- the old address keeps serving the old bytes until nothing points at it.

And nothing is ever deleted here. Because a key is derived from the bytes, two
products that happen to share a photo share a key, and removing the photo from
one would blank the other. Deleting safely needs reference counting, and an
orphaned image costs a few kilobytes - far less than that bug would.
"""
from __future__ import annotations

import hashlib
import os
import shutil
from pathlib import Path
from typing import Protocol

from django.conf import settings

#: Extensions by media type, so a stored object keeps a sensible name and a
#: filesystem store can be read by a person during an incident.
_EXTENSIONS = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/gif": "gif",
}


def content_key(payload: bytes, media_type: str, *, prefix: str = "products") -> str:
    """A stable name for these exact bytes.

    Sharded by the first two characters of the digest: a single directory
    holding a hundred thousand files is slow to list on most filesystems, and
    an object store charges for the same listing.
    """
    digest = hashlib.sha256(payload).hexdigest()
    extension = _EXTENSIONS.get(media_type, "bin")
    return f"{prefix}/{digest[:2]}/{digest}.{extension}"


class BlobStore(Protocol):
    """The whole contract. Anything satisfying it can hold the bytes."""

    def put(self, key: str, payload: bytes, media_type: str) -> None: ...

    def get(self, key: str) -> bytes | None: ...

    def exists(self, key: str) -> bool: ...


class FilesystemBlobStore:
    """Files under a directory on the machine.

    Fine for one droplet, and what runs unless something else is configured.
    The operational catch is worth being plain about: the directory has to sit
    on a volume that survives a rebuild and has to be included in backups,
    neither of which is true of a container's own disk.
    """

    def __init__(self, root: str | os.PathLike[str]):
        self.root = Path(root)

    def _path(self, key: str) -> Path:
        # Keys are generated here and never supplied by a caller, but a
        # traversal check costs nothing and this writes to a filesystem.
        resolved = (self.root / key).resolve()
        if not str(resolved).startswith(str(self.root.resolve())):
            raise ValueError("Refusing a key that points outside the store.")
        return resolved

    def put(self, key: str, payload: bytes, media_type: str) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        # Written beside the target and moved into place, so a crash midway
        # cannot leave a half-file that reads as a corrupt image forever.
        temporary = path.with_suffix(path.suffix + ".partial")
        temporary.write_bytes(payload)
        shutil.move(str(temporary), str(path))

    def get(self, key: str) -> bytes | None:
        try:
            return self._path(key).read_bytes()
        except (FileNotFoundError, ValueError, IsADirectoryError, PermissionError):
            return None

    def exists(self, key: str) -> bool:
        try:
            return self._path(key).is_file()
        except ValueError:
            return False


class S3BlobStore:
    """An S3-compatible bucket: DigitalOcean Spaces, Cloudflare R2, or AWS.

    boto3 is imported when this is constructed rather than at module load, so
    a deployment running on disk never needs the dependency installed at all.
    """

    def __init__(
        self,
        *,
        bucket: str,
        endpoint: str = "",
        region: str = "",
        access_key: str = "",
        secret_key: str = "",
    ):
        try:
            import boto3
        except ImportError as exc:  # pragma: no cover - depends on the install
            raise RuntimeError(
                "S3 storage is configured but boto3 is not installed. "
                "Install it, or set BLOB_STORE=filesystem."
            ) from exc

        self.bucket = bucket
        self.client = boto3.client(
            "s3",
            endpoint_url=endpoint or None,
            region_name=region or None,
            aws_access_key_id=access_key or None,
            aws_secret_access_key=secret_key or None,
        )

    def put(self, key: str, payload: bytes, media_type: str) -> None:
        self.client.put_object(
            Bucket=self.bucket, Key=key, Body=payload, ContentType=media_type
        )

    def get(self, key: str) -> bytes | None:
        try:
            response = self.client.get_object(Bucket=self.bucket, Key=key)
        except Exception:
            # A missing object is the ordinary case, and everything else - a
            # network blip, a stale credential - must still render as "no
            # picture" rather than a 500 on a product page.
            return None
        return response["Body"].read()

    def exists(self, key: str) -> bool:
        try:
            self.client.head_object(Bucket=self.bucket, Key=key)
        except Exception:
            return False
        return True


_store: BlobStore | None = None


def build_store() -> BlobStore:
    """The store this deployment is configured for."""
    backend = str(getattr(settings, "BLOB_STORE", "filesystem")).strip().lower()
    if backend == "s3":
        return S3BlobStore(
            bucket=getattr(settings, "BLOB_S3_BUCKET", ""),
            endpoint=getattr(settings, "BLOB_S3_ENDPOINT", ""),
            region=getattr(settings, "BLOB_S3_REGION", ""),
            access_key=getattr(settings, "BLOB_S3_ACCESS_KEY", ""),
            secret_key=getattr(settings, "BLOB_S3_SECRET_KEY", ""),
        )
    return FilesystemBlobStore(getattr(settings, "BLOB_ROOT", "/tmp/bhub-media"))


def get_store() -> BlobStore:
    """The shared store, built once.

    Cached because the S3 client opens a connection pool, and building one per
    request would spend more time on handshakes than on serving pictures.
    """
    global _store
    if _store is None:
        _store = build_store()
    return _store


def reset_store() -> None:
    """Forget the cached store. For tests that point it somewhere else."""
    global _store
    _store = None

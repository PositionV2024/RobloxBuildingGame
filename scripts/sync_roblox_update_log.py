#!/usr/bin/env python3
"""Sync reviewed GitHub Releases to Roblox and upload one optional release image.

Python 3.10+ standard library only.

Text path:
    GitHub Release -> dedicated Roblox DataStore feed

Image path:
    GitHub Release attachment -> Roblox Open Cloud Assets API -> imageAssetId in feed

Production environment:
    GITHUB_REPOSITORY
    GITHUB_TOKEN
    ROBLOX_UNIVERSE_ID
    ROBLOX_API_KEY

Required only when an eligible release contains an image attachment that has not
already been uploaded:
    ROBLOX_ASSET_API_KEY
    ROBLOX_ASSET_CREATOR_TYPE   (user or group)
    ROBLOX_ASSET_CREATOR_ID     (numeric user/group ID)

The asset API key should be a separate least-privilege key with Assets Read/Write.
The DataStore key does not need Assets permissions.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import random
import re
import struct
import sys
import time
import uuid
from datetime import datetime
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

STORE = "ParkourUpdateLogs_V1"
ENTRY = "release_feed_v1"
START = "<!-- ROBLOX:START -->"
END = "<!-- ROBLOX:END -->"
MAX_RELEASES = 20
MAX_BODY_BYTES = 4000
MAX_PAYLOAD_BYTES = 120_000
MAX_PAGES = 10
RETRIES = 4
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_IMAGE_DIMENSION_EXCLUSIVE = 8000
ASSET_OPERATION_TIMEOUT = 120
GITHUB_API_VERSION = "2026-03-10"

SUPPORTED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg"}
PREFERRED_IMAGE_NAMES = {
    "roblox-update.png", "roblox-update.jpg", "roblox-update.jpeg",
    "update-banner.png", "update-banner.jpg", "update-banner.jpeg",
    "banner.png", "banner.jpg", "banner.jpeg",
}


class SyncError(Exception):
    pass


class ApiError(SyncError):
    def __init__(self, status: int, host: str):
        self.status = status
        super().__init__(f"{host}: HTTP {status}. Check credentials, permissions, and configuration.")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward authorization headers through an implicit redirect.
        return None


OPENER = build_opener(NoRedirect())


def request_json(method: str, url: str, headers: dict[str, str], payload: Any = None) -> Any:
    data = None if payload is None else json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8")
    host = "Roblox API" if url.startswith("https://apis.roblox.com/") else "GitHub API"
    for attempt in range(RETRIES):
        retry_after = 0.0
        try:
            req = Request(url, data=data, headers=headers, method=method)
            with OPENER.open(req, timeout=30) as response:
                raw = response.read(8_000_001)
                if len(raw) > 8_000_000:
                    raise SyncError(f"{host}: response exceeded the safety size limit.")
                return json.loads(raw.decode("utf-8")) if raw else {}
        except HTTPError as exc:
            status = exc.code
            retryable = status in {408, 429, 500, 502, 503, 504}
            try:
                retry_after = min(30.0, max(0.0, float(exc.headers.get("Retry-After", "0"))))
            except (TypeError, ValueError):
                pass
            exc.close()
            if not retryable or attempt == RETRIES - 1:
                raise ApiError(status, host) from None
        except (URLError, TimeoutError, ConnectionError):
            if attempt == RETRIES - 1:
                raise SyncError(f"{host}: connection failed after retries; existing log was not deliberately cleared.") from None
        except (UnicodeError, json.JSONDecodeError):
            raise SyncError(f"{host}: returned invalid JSON.") from None
        time.sleep(max(retry_after, 2 ** attempt + random.uniform(0, 0.25)))
    raise SyncError(f"{host}: request failed.")


def clean_plain_text(text: str) -> str:
    """Small Markdown-to-plain-text converter; release text is never executed."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    text = re.sub(r"!\[[^\]]*\]\([^\n)]*\)", "", text)
    text = re.sub(r"\[([^\]]+)\]\([^\n)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = re.sub(r"https?://\S+|www\.\S+", "", text)
    text = re.sub(r"^\s*```[^\n]*$", "", text, flags=re.M)
    text = re.sub(r"^\s{0,3}#{1,6}\s+", "", text, flags=re.M)
    text = re.sub(r"^\s*[-*+]\s+", "• ", text, flags=re.M)
    text = re.sub(r"^\s*>\s?", "", text, flags=re.M)
    for marker in ("**", "__", "~~", "`"):
        text = text.replace(marker, "")
    text = "".join(ch for ch in text if ch in "\n\t" or (ord(ch) >= 32 and ord(ch) != 127))
    text = "\n".join(line.rstrip() for line in text.splitlines())
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def bounded(text: str, size: int, field: str, release_id: int) -> str:
    if not text or len(text.encode("utf-8")) > size:
        raise SyncError(f"Release {release_id}: {field} must be nonempty and no more than {size} UTF-8 bytes.")
    return text


def unix_time(value: Any) -> int:
    if not isinstance(value, str):
        raise SyncError("Published release is missing a valid published_at timestamp.")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError("missing timezone")
        result = int(parsed.timestamp())
        if result <= 0:
            raise ValueError("invalid timestamp")
        return result
    except (ValueError, OverflowError):
        raise SyncError("Published release has an invalid timestamp.") from None


def valid_repo(repo: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise SyncError("Set GITHUB_REPOSITORY to owner/repository (not a URL).")
    return repo


def valid_positive_id(value: str, field: str) -> str:
    value = value.strip()
    if not value.isdigit() or int(value) <= 0:
        raise SyncError(f"{field} must be a positive numeric ID.")
    return value


def select_release_image(release: dict[str, Any]) -> dict[str, Any] | None:
    """Choose one GitHub Release attachment deterministically.

    Preferred names win. Otherwise a single attached PNG/JPG/JPEG is accepted.
    Multiple non-preferred images are rejected so the workflow never guesses.
    """
    assets = release.get("assets") or []
    if not isinstance(assets, list):
        raise SyncError(f"Release {release.get('id')}: assets field was not a list.")

    images: list[dict[str, Any]] = []
    for asset in assets:
        if not isinstance(asset, dict) or asset.get("state") not in {None, "uploaded"}:
            continue
        name = str(asset.get("name") or "")
        suffix = Path(name.lower()).suffix
        if suffix not in SUPPORTED_IMAGE_EXTENSIONS:
            continue
        ident = asset.get("id")
        size = asset.get("size")
        url = asset.get("url")
        if type(ident) is not int or ident <= 0 or not isinstance(url, str) or not url.startswith("https://api.github.com/"):
            raise SyncError(f"Release {release.get('id')}: image attachment metadata is incomplete.")
        if type(size) is not int or size <= 0:
            raise SyncError(f"Release {release.get('id')}: image attachment has an invalid size.")
        if size > MAX_IMAGE_BYTES:
            raise SyncError(f"Release {release.get('id')}: image attachment exceeds Roblox's 20 MB upload limit.")
        images.append(asset)

    if not images:
        return None

    preferred = [a for a in images if str(a.get("name") or "").lower() in PREFERRED_IMAGE_NAMES]
    if len(preferred) == 1:
        return preferred[0]
    if len(preferred) > 1:
        raise SyncError(f"Release {release.get('id')}: multiple preferred update images are attached; keep only one.")
    if len(images) == 1:
        return images[0]
    raise SyncError(
        f"Release {release.get('id')}: multiple image attachments found. "
        "Rename the intended banner to roblox-update.png (or .jpg/.jpeg)."
    )


def normalize_release(release: dict[str, Any]) -> dict[str, Any] | None:
    if release.get("draft") or release.get("prerelease") or not release.get("published_at"):
        return None
    raw = release.get("body") or ""
    if not isinstance(raw, str):
        raise SyncError("Release body must be text.")
    if START not in raw and END not in raw:
        return None
    if raw.count(START) != 1 or raw.count(END) != 1 or raw.index(END) < raw.index(START):
        raise SyncError("Release has malformed ROBLOX notes markers. Use the supplied template exactly.")
    ident = release.get("id")
    if type(ident) is not int or ident <= 0:
        raise SyncError("Release is missing its numeric GitHub release ID.")

    body = clean_plain_text(raw.split(START, 1)[1].split(END, 1)[0])
    tag = clean_plain_text(str(release.get("tag_name") or "")).replace("\n", " ")
    title = clean_plain_text(str(release.get("name") or tag)).replace("\n", " ")
    image = select_release_image(release)

    item: dict[str, Any] = {
        "id": f"gh-{ident}",
        "version": bounded(tag, 64, "version tag", ident),
        "title": bounded(title, 160, "title", ident),
        "publishedAt": unix_time(release["published_at"]),
        "body": bounded(body, MAX_BODY_BYTES, "player-facing notes", ident),
    }
    if image:
        # Internal metadata used by the publisher. _githubImage is removed before
        # the DataStore payload is built.
        item["_githubImage"] = {
            "id": str(image["id"]),
            "name": str(image.get("name") or ""),
            "size": int(image["size"]),
            "url": image["url"],
            "digest": str(image.get("digest") or ""),
            "label": clean_plain_text(str(image.get("label") or ""))[:240],
        }
    return item


def prepare_entries(releases: list[Any], repo: str) -> list[dict[str, Any]]:
    valid_repo(repo)
    if not isinstance(releases, list):
        raise SyncError("Expected a JSON array of GitHub releases.")
    entries: dict[str, dict[str, Any]] = {}
    for release in releases:
        if not isinstance(release, dict):
            raise SyncError("Unexpected GitHub release data; refusing to replace the log.")
        item = normalize_release(release)
        if item:
            if item["id"] in entries and entries[item["id"]] != item:
                raise SyncError("Release changed during pagination; rerun the workflow.")
            entries[item["id"]] = item
    return sorted(entries.values(), key=lambda x: (x["publishedAt"], int(x["id"][3:])), reverse=True)[:MAX_RELEASES]


def fetch_releases(repo: str, token: str) -> list[dict[str, Any]]:
    valid_repo(repo)
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "ParkourUpdateLog/2.0",
        "X-GitHub-Api-Version": GITHUB_API_VERSION,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    entries = []
    for page in range(1, MAX_PAGES + 1):
        batch = request_json("GET", f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}", headers)
        if not isinstance(batch, list):
            raise SyncError("GitHub release listing failed; existing feed is unchanged.")
        entries.extend(batch)
        if len(batch) < 100:
            return entries
    raise SyncError("More than the safe pagination limit. Review MAX_PAGES before syncing this repository.")


def datastore_url(universe_id: str) -> str:
    valid_positive_id(universe_id, "ROBLOX_UNIVERSE_ID")
    return f"https://apis.roblox.com/cloud/v2/universes/{universe_id}/data-stores/{quote(STORE, safe='')}/scopes/global/entries/{quote(ENTRY, safe='')}"


def get_current_feed(universe_id: str, key: str) -> dict[str, Any]:
    if not key:
        raise SyncError("ROBLOX_API_KEY is missing. Add it as a GitHub Actions secret.")
    url = datastore_url(universe_id)
    headers = {"x-api-key": key, "Content-Type": "application/json", "User-Agent": "ParkourUpdateLog/2.0"}
    try:
        current = request_json("GET", url, headers)
    except ApiError as exc:
        if exc.status == 404:
            raise SyncError("Roblox log entry not found. Run ParkourUpdateLogServer in this published experience once, then retry.") from None
        raise
    old = current.get("value") if isinstance(current, dict) else None
    if not isinstance(old, dict) or old.get("schemaVersion") != 1:
        raise SyncError("Unexpected data at the log key. Refusing to overwrite it.")
    return old


def github_asset_download(asset: dict[str, Any], token: str) -> bytes:
    """Download a GitHub release asset without forwarding the GitHub token to a CDN."""
    url = asset["url"]
    headers = {
        "Accept": "application/octet-stream",
        "User-Agent": "ParkourUpdateLog/2.0",
        "X-GitHub-Api-Version": GITHUB_API_VERSION,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    try:
        req = Request(url, headers=headers, method="GET")
        with OPENER.open(req, timeout=60) as response:
            raw = response.read(MAX_IMAGE_BYTES + 1)
    except HTTPError as exc:
        if exc.code not in {301, 302, 303, 307, 308}:
            status = exc.code
            exc.close()
            raise ApiError(status, "GitHub API") from None
        location = exc.headers.get("Location", "")
        exc.close()
        parsed = urlparse(location)
        host = (parsed.hostname or "").lower()
        allowed = parsed.scheme == "https" and (
            host == "github.com" or host.endswith(".githubusercontent.com") or host.endswith(".github.com")
        )
        if not allowed:
            raise SyncError("GitHub asset download redirected to an unexpected host; download stopped.")
        # Signed CDN URL: deliberately omit Authorization.
        try:
            req = Request(location, headers={"User-Agent": "ParkourUpdateLog/2.0"}, method="GET")
            with build_opener().open(req, timeout=60) as response:
                raw = response.read(MAX_IMAGE_BYTES + 1)
        except (HTTPError, URLError, TimeoutError, ConnectionError) as download_error:
            if isinstance(download_error, HTTPError):
                download_error.close()
            raise SyncError("GitHub release image download failed.") from None
    except (URLError, TimeoutError, ConnectionError):
        raise SyncError("GitHub release image download failed.") from None

    if not raw or len(raw) > MAX_IMAGE_BYTES:
        raise SyncError("GitHub release image is empty or exceeds Roblox's 20 MB upload limit.")
    return raw


def detect_image(data: bytes) -> tuple[str, str, int, int]:
    """Return (mime, normalized extension, width, height) for PNG/JPEG."""
    if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
        width, height = struct.unpack(">II", data[16:24])
        return "image/png", ".png", width, height

    if data.startswith(b"\xff\xd8"):
        index = 2
        sof_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
        while index + 4 <= len(data):
            if data[index] != 0xFF:
                index += 1
                continue
            while index < len(data) and data[index] == 0xFF:
                index += 1
            if index >= len(data):
                break
            marker = data[index]
            index += 1
            if marker in {0xD8, 0xD9}:
                continue
            if marker == 0xDA:  # Start of scan; SOF should have appeared already.
                break
            if index + 2 > len(data):
                break
            segment_length = struct.unpack(">H", data[index:index + 2])[0]
            if segment_length < 2 or index + segment_length > len(data):
                break
            if marker in sof_markers and segment_length >= 7:
                height, width = struct.unpack(">HH", data[index + 3:index + 7])
                return "image/jpeg", ".jpeg", width, height
            index += segment_length
        raise SyncError("JPEG release image dimensions could not be read.")

    raise SyncError("Release image must be a real PNG or JPEG file.")


def validate_image_dimensions(width: int, height: int) -> None:
    if width <= 0 or height <= 0:
        raise SyncError("Release image has invalid dimensions.")
    if width >= MAX_IMAGE_DIMENSION_EXCLUSIVE or height >= MAX_IMAGE_DIMENSION_EXCLUSIVE:
        raise SyncError("Release image must be smaller than 8000x8000 pixels for Roblox.")


def multipart_asset_request(metadata: dict[str, Any], image: bytes, mime: str, extension: str) -> tuple[bytes, str]:
    boundary = "----ParkourUpdateLog" + uuid.uuid4().hex
    crlf = b"\r\n"
    chunks: list[bytes] = []

    def field(name: str, content: bytes, content_type: str | None = None, filename: str | None = None) -> None:
        chunks.append(f"--{boundary}".encode() + crlf)
        disposition = f'Content-Disposition: form-data; name="{name}"'
        if filename:
            disposition += f'; filename="{filename}"'
        chunks.append(disposition.encode() + crlf)
        if content_type:
            chunks.append(f"Content-Type: {content_type}".encode() + crlf)
        chunks.append(crlf)
        chunks.append(content)
        chunks.append(crlf)

    field("request", json.dumps(metadata, ensure_ascii=False, separators=(",", ":")).encode("utf-8"), "application/json")
    field("fileContent", image, mime, "update-banner" + extension)
    chunks.append(f"--{boundary}--".encode() + crlf)
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def asset_creator() -> dict[str, str]:
    creator_type = os.environ.get("ROBLOX_ASSET_CREATOR_TYPE", "").strip().lower()
    creator_id = valid_positive_id(os.environ.get("ROBLOX_ASSET_CREATOR_ID", ""), "ROBLOX_ASSET_CREATOR_ID")
    if creator_type == "user":
        return {"userId": creator_id}
    if creator_type == "group":
        return {"groupId": creator_id}
    raise SyncError("ROBLOX_ASSET_CREATOR_TYPE must be either 'user' or 'group'.")


def upload_roblox_image(image: bytes, mime: str, extension: str, entry: dict[str, Any], api_key: str) -> tuple[str, str]:
    if not api_key:
        raise SyncError(
            "A release image needs ROBLOX_ASSET_API_KEY. Add a Roblox Assets Read/Write API key as a GitHub Actions secret."
        )
    creator = asset_creator()
    display = f"Update {entry['version']} - {entry['title']}"[:50].strip()
    description = f"Automatic update-log banner for {os.environ.get('GITHUB_REPOSITORY', 'Roblox game')} {entry['version']}"[:200]
    metadata = {
        "assetType": "Decal",
        "displayName": display or f"Update {entry['version']}",
        "description": description,
        "creationContext": {"creator": creator},
    }
    body, content_type = multipart_asset_request(metadata, image, mime, extension)
    headers = {
        "x-api-key": api_key,
        "Content-Type": content_type,
        "Content-Length": str(len(body)),
        "User-Agent": "ParkourUpdateLog/2.0",
    }

    # Create Asset is not automatically retried because POST is not idempotent.
    try:
        req = Request("https://apis.roblox.com/assets/v1/assets", data=body, headers=headers, method="POST")
        with OPENER.open(req, timeout=60) as response:
            raw = response.read(1_000_001)
            if len(raw) > 1_000_000:
                raise SyncError("Roblox Assets API response was unexpectedly large.")
            operation = json.loads(raw.decode("utf-8")) if raw else {}
    except HTTPError as exc:
        status = exc.code
        exc.close()
        raise ApiError(status, "Roblox Assets API") from None
    except (URLError, TimeoutError, ConnectionError):
        raise SyncError(
            "Roblox image upload connection failed. The release feed was not changed. "
            "Check Creator Hub before retrying because an upload may have been accepted before the connection failed."
        ) from None
    except (UnicodeError, json.JSONDecodeError):
        raise SyncError("Roblox Assets API returned invalid JSON while creating the release image.") from None

    path = operation.get("path") if isinstance(operation, dict) else None
    if not isinstance(path, str) or not re.fullmatch(r"operations/[A-Za-z0-9._~%-]+", path):
        raise SyncError("Roblox Assets API did not return a valid operation path.")

    operation_url = "https://apis.roblox.com/assets/v1/" + path
    deadline = time.monotonic() + ASSET_OPERATION_TIMEOUT
    while time.monotonic() < deadline:
        result = request_json("GET", operation_url, {"x-api-key": api_key, "User-Agent": "ParkourUpdateLog/2.0"})
        if isinstance(result, dict) and result.get("done") is True:
            error = result.get("error")
            if error:
                message = error.get("message") if isinstance(error, dict) else None
                raise SyncError("Roblox image upload operation failed" + (f": {str(message)[:200]}" if message else "."))
            response = result.get("response")
            if not isinstance(response, dict):
                raise SyncError("Roblox image upload completed without asset information.")
            asset_id = str(response.get("assetId") or "")
            if not asset_id.isdigit() or int(asset_id) <= 0:
                raise SyncError("Roblox image upload completed without a valid asset ID.")
            moderation = response.get("moderationResult")
            moderation_state = ""
            if isinstance(moderation, dict):
                moderation_state = str(moderation.get("moderationState") or "")
            if "REJECT" in moderation_state.upper():
                raise SyncError("Roblox rejected the release image during moderation; update log was not changed.")
            return asset_id, moderation_state
        time.sleep(2)
    raise SyncError("Roblox image upload is still processing after 120 seconds; update log was not changed.")


def old_entries_by_id(old_feed: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    entries = old_feed.get("entries")
    if not isinstance(entries, list):
        return result
    for entry in entries:
        if isinstance(entry, dict) and isinstance(entry.get("id"), str):
            result[entry["id"]] = entry
    return result


def reuse_or_upload_images(
    entries: list[dict[str, Any]], old_feed: dict[str, Any], github_token: str, asset_key: str
) -> list[dict[str, Any]]:
    previous = old_entries_by_id(old_feed)
    final: list[dict[str, Any]] = []

    for entry in entries:
        source = entry.pop("_githubImage", None)
        out = dict(entry)
        if source:
            source_id = source["id"]
            source_digest = source.get("digest") or ""
            prior = previous.get(entry["id"], {})
            prior_asset_id = str(prior.get("imageAssetId") or "")
            same_source = str(prior.get("imageSourceId") or "") == source_id
            if source_digest and prior.get("imageSourceDigest"):
                same_source = same_source and str(prior.get("imageSourceDigest")) == source_digest

            if same_source and prior_asset_id.isdigit() and int(prior_asset_id) > 0:
                out["imageAssetId"] = prior_asset_id
                out["imageSourceId"] = source_id
                if source_digest:
                    out["imageSourceDigest"] = source_digest
                print(f"Reusing Roblox image asset {prior_asset_id} for {entry['version']}.")
            else:
                print(f"Uploading attached release image for {entry['version']} to Roblox...")
                image = github_asset_download(source, github_token)
                mime, extension, width, height = detect_image(image)
                validate_image_dimensions(width, height)
                asset_id, moderation_state = upload_roblox_image(image, mime, extension, entry, asset_key)
                out["imageAssetId"] = asset_id
                out["imageSourceId"] = source_id
                if source_digest:
                    out["imageSourceDigest"] = source_digest
                if source.get("label"):
                    out["imageCaption"] = source["label"]
                state_text = moderation_state or "status not returned"
                print(f"Uploaded Roblox image asset {asset_id} for {entry['version']} ({state_text}).")
        final.append(out)
    return final


def build_feed(entries: list[dict[str, Any]], repo: str) -> dict[str, Any]:
    canonical = {"schemaVersion": 1, "sourceRepository": repo, "entries": entries}
    digest = hashlib.sha256(
        json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    feed = {**canonical, "fingerprint": digest, "generatedAt": int(time.time())}
    if len(json.dumps(feed, ensure_ascii=False).encode("utf-8")) > MAX_PAYLOAD_BYTES:
        raise SyncError("Feed is too large. Shorten the release notes.")
    return feed


def write_feed(feed: dict[str, Any], old: dict[str, Any], universe_id: str, key: str, allow_empty: bool) -> bool:
    if old.get("sourceRepository") and str(old["sourceRepository"]).lower() != str(feed["sourceRepository"]).lower():
        raise SyncError("This Roblox feed is assigned to a DIFFERENT repository. Check the Universe ID; no write made.")
    if not feed["entries"] and old.get("entries") and not allow_empty:
        raise SyncError(
            "This would empty a nonempty log. Check your notes markers. "
            "Manual Run workflow with allow_empty=true is required to clear it."
        )
    if old.get("fingerprint") == feed["fingerprint"]:
        print("No player-facing changes; no Roblox write needed.")
        return False

    url = datastore_url(universe_id)
    headers = {"x-api-key": key, "Content-Type": "application/json", "User-Agent": "ParkourUpdateLog/2.0"}
    request_json("PATCH", url, headers, {"value": feed})
    for attempt in range(4):
        check = request_json("GET", url, headers)
        if isinstance(check, dict) and isinstance(check.get("value"), dict) and check["value"].get("fingerprint") == feed["fingerprint"]:
            print(f"Verified Roblox update log: {len(feed['entries'])} entries.")
            return True
        time.sleep(2 ** attempt)
    raise SyncError("Write was sent but verification did not see it yet. Check the entry before retrying; do not assume the write failed.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, help="Offline JSON release list, for testing only")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--dry-run", action="store_true", help="Validate release notes and image selection only; never write/upload")
    args = parser.parse_args()

    repo = valid_repo(args.repo)
    github_token = os.environ.get("GITHUB_TOKEN", "")
    if args.fixture and not args.dry_run:
        raise SyncError("Fixtures are restricted to --dry-run to prevent publishing example notes.")
    if args.fixture:
        releases = json.loads(args.fixture.read_text(encoding="utf-8"))
    else:
        releases = fetch_releases(repo, github_token)

    entries = prepare_entries(releases, repo)
    image_count = sum(1 for entry in entries if entry.get("_githubImage"))
    print(f"Prepared {len(entries)} reviewed, stable release entries; {image_count} release image attachment(s) selected.")

    dry_run = args.dry_run or os.environ.get("ROBLOX_DRY_RUN", "").lower() == "true"
    if dry_run:
        for entry in entries:
            source = entry.get("_githubImage")
            if source:
                print(f"Dry run image: {entry['version']} -> {source['name']} ({source['size']} bytes).")
        print("Dry run complete: no GitHub image download, Roblox asset upload, or DataStore write performed.")
        return 0

    universe_id = os.environ.get("ROBLOX_UNIVERSE_ID", "").strip()
    datastore_key = os.environ.get("ROBLOX_API_KEY", "")
    old = get_current_feed(universe_id, datastore_key)

    # Protect against accidental total clearing BEFORE creating any new assets.
    allow_empty = os.environ.get("ROBLOX_ALLOW_EMPTY", "").lower() == "true"
    if not entries and old.get("entries") and not allow_empty:
        raise SyncError(
            "This would empty a nonempty log. Check your notes markers. "
            "Manual Run workflow with allow_empty=true is required to clear it."
        )

    asset_key = os.environ.get("ROBLOX_ASSET_API_KEY", "")
    entries = reuse_or_upload_images(entries, old, github_token, asset_key)
    feed = build_feed(entries, repo)
    write_feed(feed, old, universe_id, datastore_key, allow_empty)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (SyncError, OSError, json.JSONDecodeError) as exc:
        # Never print credentials or binary release contents.
        print(f"Update-log sync stopped: {exc}", file=sys.stderr)
        sys.exit(1)

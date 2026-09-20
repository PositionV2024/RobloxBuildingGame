#!/usr/bin/env python3
"""Publish reviewed GitHub release notes to ONE dedicated Roblox DataStore entry.

Python 3.10+ standard library only. Never executes release text as code.
The Roblox server seeds the entry first, so this key needs read/update scopes only.
Production: GITHUB_REPOSITORY, GITHUB_TOKEN, ROBLOX_UNIVERSE_ID, ROBLOX_API_KEY.
Offline: --fixture examples/releases.json --repo example/parkour --dry-run
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
import sys
import time
from datetime import datetime, timezone
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
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


class SyncError(Exception):
    pass


class ApiError(SyncError):
    def __init__(self, status: int, host: str):
        self.status = status
        super().__init__(f"{host}: HTTP {status}. Check credentials, permissions, and configuration.")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Credentials must never be forwarded to an unexpected host.
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
    """A deliberately small Markdown-to-plain-text converter, not a renderer."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    # No images, embedded HTML, clickable external links, or executable markup.
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


def normalize_release(release: dict[str, Any]) -> dict[str, Any] | None:
    if release.get("draft") or release.get("prerelease") or not release.get("published_at"):
        return None
    raw = release.get("body") or ""
    if not isinstance(raw, str):
        raise SyncError("Release body must be text.")
    if START not in raw and END not in raw:
        return None  # Explicitly opt in: only reviewed game-facing notes are exported.
    if raw.count(START) != 1 or raw.count(END) != 1 or raw.index(END) < raw.index(START):
        raise SyncError("Release has malformed ROBLOX notes markers. Use the supplied template exactly.")
    ident = release.get("id")
    if type(ident) is not int or ident <= 0:
        raise SyncError("Release is missing its numeric GitHub release ID.")
    body = clean_plain_text(raw.split(START, 1)[1].split(END, 1)[0])
    tag = clean_plain_text(str(release.get("tag_name") or "")).replace("\n", " ")
    title = clean_plain_text(str(release.get("name") or tag)).replace("\n", " ")
    return {
        "id": f"gh-{ident}",
        "version": bounded(tag, 64, "version tag", ident),
        "title": bounded(title, 160, "title", ident),
        "publishedAt": unix_time(release["published_at"]),
        "body": bounded(body, MAX_BODY_BYTES, "player-facing notes", ident),
    }


def valid_repo(repo: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise SyncError("Set GITHUB_REPOSITORY to owner/repository (not a URL).")
    return repo


def build_feed(releases: list[Any], repo: str) -> dict[str, Any]:
    valid_repo(repo)
    if not isinstance(releases, list):
        raise SyncError("Expected a JSON array of GitHub releases.")
    entries: dict[str, dict[str, Any]] = {}
    for release in releases:
        if not isinstance(release, dict):
            raise SyncError("Unexpected GitHub release data; refusing to replace the log.")
        item = normalize_release(release)
        if item:
            # Duplicated IDs are one logical entry, not two announcements.
            if item["id"] in entries and entries[item["id"]] != item:
                raise SyncError("Release changed during pagination; rerun the workflow.")
            entries[item["id"]] = item
    ordered = sorted(entries.values(), key=lambda x: (x["publishedAt"], int(x["id"][3:])), reverse=True)[:MAX_RELEASES]
    canonical = {"schemaVersion": 1, "sourceRepository": repo, "entries": ordered}
    digest = hashlib.sha256(json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    feed = {**canonical, "fingerprint": digest, "generatedAt": int(time.time())}
    if len(json.dumps(feed, ensure_ascii=False).encode("utf-8")) > MAX_PAYLOAD_BYTES:
        raise SyncError("Feed is too large. Shorten the release notes.")
    return feed


def fetch_releases(repo: str, token: str) -> list[dict[str, Any]]:
    valid_repo(repo)
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "ParkourUpdateLog/1.0", "X-GitHub-Api-Version": "2022-11-28"}
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


def sync_feed(feed: dict[str, Any], universe_id: str, key: str, allow_empty: bool = False) -> bool:
    if not universe_id.isdigit() or int(universe_id) <= 0:
        raise SyncError("Set ROBLOX_UNIVERSE_ID to the positive game.GameId, not a UserId or PlaceId.")
    if not key:
        raise SyncError("ROBLOX_API_KEY is missing. Add it as a GitHub Actions secret.")
    url = f"https://apis.roblox.com/cloud/v2/universes/{universe_id}/data-stores/{quote(STORE, safe='')}/scopes/global/entries/{quote(ENTRY, safe='')}"
    headers = {"x-api-key": key, "Content-Type": "application/json", "User-Agent": "ParkourUpdateLog/1.0"}
    try:
        current = request_json("GET", url, headers)
    except ApiError as exc:
        if exc.status == 404:
            raise SyncError("Roblox log entry not found. Run ParkourUpdateLogServer in this published experience once (not Studio demo mode), then retry. Also check your Universe ID.") from None
        raise
    old = current.get("value") if isinstance(current, dict) else None
    if not isinstance(old, dict) or old.get("schemaVersion") != 1:
        raise SyncError("Unexpected data at the log key. Refusing to overwrite it.")
    if old.get("sourceRepository") and old["sourceRepository"].lower() != feed["sourceRepository"].lower():
        raise SyncError("This Roblox feed is assigned to a DIFFERENT repository. Check the Universe ID; no write made.")
    if not feed["entries"] and old.get("entries") and not allow_empty:
        raise SyncError("This would empty a nonempty log. Check your notes markers. Manual Run workflow with allow_empty=true is required to clear it.")
    if old.get("fingerprint") == feed["fingerprint"]:
        print("No player-facing changes; no Roblox write needed.")
        return False
    # A single Actions concurrency group is the sole feed writer. The game only
    # creates an absent seed; it never overwrites an existing published feed.
    request_json("PATCH", url, headers, {"value": feed})
    for attempt in range(4):
        check = request_json("GET", url, headers)
        if isinstance(check, dict) and isinstance(check.get("value"), dict) and check["value"].get("fingerprint") == feed["fingerprint"]:
            print(f"Verified Roblox update log: {len(feed['entries'])} entries. Other DataStores were not accessed.")
            return True
        time.sleep(2 ** attempt)
    raise SyncError("Write was sent but verification did not see it yet. Check the entry before retrying; do not assume the write failed.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, help="Offline JSON release list, for testing only")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--dry-run", action="store_true", help="Validate only, never write to Roblox")
    args = parser.parse_args()
    if args.fixture and not args.dry_run:
        raise SyncError("Fixtures are restricted to --dry-run to prevent publishing example notes.")
    if args.fixture:
        releases = json.loads(args.fixture.read_text(encoding="utf-8"))
    else:
        releases = fetch_releases(args.repo, os.environ.get("GITHUB_TOKEN", ""))
    feed = build_feed(releases, args.repo)
    print(f"Prepared {len(feed['entries'])} reviewed, stable release entries.")
    if args.dry_run or os.environ.get("ROBLOX_DRY_RUN", "").lower() == "true":
        print("Dry run complete: no Roblox request/write performed.")
        return 0
    sync_feed(feed, os.environ.get("ROBLOX_UNIVERSE_ID", "").strip(), os.environ.get("ROBLOX_API_KEY", ""), os.environ.get("ROBLOX_ALLOW_EMPTY", "").lower() == "true")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (SyncError, OSError, json.JSONDecodeError) as exc:
        # No request bodies, release contents, or credentials in CI error output.
        print(f"Update-log sync stopped: {exc}", file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any


def _slug(text: str) -> str:
    cleaned = [
        ch.lower() if ch.isalnum() else "-"
        for ch in text
    ]
    collapsed = "".join(cleaned).strip("-")
    while "--" in collapsed:
        collapsed = collapsed.replace("--", "-")
    return collapsed or "repo"


def _cache_name(repo: dict[str, Any]) -> str:
    repo_id = str(repo.get("id", "repo"))
    github = repo.get("github", {})
    github_repo = str(github.get("repo", ""))
    github_ref = str(github.get("ref", ""))
    digest = hashlib.sha256(f"{github_repo}@{github_ref}".encode("utf-8")).hexdigest()[:10]
    return f"{_slug(repo_id)}-{digest}"


def _run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd is not None else None,
        text=True,
        capture_output=True,
        check=False,
    )


def _metadata_matches(meta_path: Path, github_repo: str, github_ref: str) -> bool:
    if not meta_path.exists():
        return False
    try:
        metadata = json.loads(meta_path.read_text())
    except Exception:
        return False
    return metadata == {"repo": github_repo, "ref": github_ref}


def _clone_github_repo(checkout_root: Path, github_repo: str, github_ref: str) -> None:
    if checkout_root.exists():
        shutil.rmtree(checkout_root)

    clone = _run(
        [
            "gh",
            "repo",
            "clone",
            github_repo,
            str(checkout_root),
            "--",
            "--depth",
            "1",
            "--branch",
            github_ref,
        ]
    )
    if clone.returncode != 0:
        raise RuntimeError(
            "failed to clone GitHub source {repo}@{ref}: {stderr}".format(
                repo=github_repo,
                ref=github_ref,
                stderr=(clone.stderr or clone.stdout).strip() or "unknown error",
            )
        )

    metadata_path = checkout_root / ".cbm-source.json"
    metadata_path.write_text(json.dumps({"repo": github_repo, "ref": github_ref}, indent=2) + "\n")


def resolve_repo_source(repo: dict[str, Any], root: Path, cache_root: Path) -> dict[str, Any]:
    github = repo.get("github")
    if github is None:
        repo_path = Path(str(repo["path"]))
        resolved = (root / repo_path).resolve()
        return {
            "path": resolved,
            "checkout_root": resolved,
            "source": {
                "kind": "local",
                "path": str(repo_path),
            },
        }

    github_repo = str(github["repo"])
    github_ref = str(github["ref"])
    github_subpath = Path(str(github.get("subpath", ".")))

    cache_root.mkdir(parents=True, exist_ok=True)
    checkout_root = cache_root / _cache_name(repo)
    metadata_path = checkout_root / ".cbm-source.json"
    if not _metadata_matches(metadata_path, github_repo, github_ref):
        _clone_github_repo(checkout_root, github_repo, github_ref)

    resolved_path = (checkout_root / github_subpath).resolve()
    if not resolved_path.exists():
        raise FileNotFoundError(
            "github source path does not exist for {repo}@{ref}: {path}".format(
                repo=github_repo,
                ref=github_ref,
                path=resolved_path,
            )
        )

    rev_parse = _run(["git", "-C", str(checkout_root), "rev-parse", "HEAD"])
    resolved_commit = rev_parse.stdout.strip() if rev_parse.returncode == 0 else ""

    return {
        "path": resolved_path,
        "checkout_root": checkout_root,
        "source": {
            "kind": "github",
            "repo": github_repo,
            "ref": github_ref,
            "subpath": str(github_subpath),
            "resolved_commit": resolved_commit,
        },
    }

#!/usr/bin/env python3
"""Paste Voxtype's already-populated clipboard using Omarchy's focus rules."""

from __future__ import annotations

import json
import hashlib
import os
import pathlib
import subprocess
import stat
import sys
import time

MAX_CLIPBOARD_BYTES = 8 * 1024 * 1024
CHUNK_BYTES = 64 * 1024


def state_marker_path() -> pathlib.Path:
    """Marker path inside a private per-user runtime directory.

    The /tmp fallback is intentionally gone: a predictable shared directory
    would let any local user pre-place or swap the marker file.
    """
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        raise RuntimeError(
            "XDG_RUNTIME_DIR is not set; refusing to store clipboard state "
            "in a world-readable location"
        )
    directory = pathlib.Path(runtime_dir) / "voxtype-enhance"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if info.st_uid != os.geteuid() or not stat.S_ISDIR(info.st_mode):
        raise RuntimeError("voxtype-enhance state directory is not a private directory")
    os.chmod(directory, 0o700)
    return directory / "clipboard-before.sha256"


def write_marker(path: pathlib.Path, marker: str) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="ascii") as handle:
        handle.write(marker)


def read_marker(path: pathlib.Path) -> str | None:
    """Read the marker only when it is a regular file owned by this user."""
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return None
    with os.fdopen(descriptor, "r", encoding="ascii") as handle:
        info = os.fstat(handle.fileno())
        if info.st_uid != os.geteuid() or not stat.S_ISREG(info.st_mode):
            return None
        return handle.read(128).strip()


def clipboard_digest() -> str | None:
    """Hash clipboard text by streaming it in bounded chunks.

    Never holds more than one chunk in memory, and stops reading at
    MAX_CLIPBOARD_BYTES so a hostile endless source cannot pin the shell;
    the digest is flagged as truncated instead.
    """
    try:
        process = subprocess.Popen(
            ["wl-paste", "--no-newline", "--type", "text/plain"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return None
    hasher = hashlib.sha256()
    total = 0
    truncated = False
    stream = process.stdout
    try:
        while stream is not None:
            chunk = stream.read(CHUNK_BYTES)
            if not chunk:
                break
            hasher.update(chunk)
            total += len(chunk)
            if total >= MAX_CLIPBOARD_BYTES:
                truncated = True
                break
    finally:
        if truncated:
            process.kill()
        process.wait()
    if total == 0 or (process.returncode != 0 and not truncated):
        return None
    digest = hasher.hexdigest()
    return f"truncated:{digest}" if truncated else digest


def snapshot_clipboard() -> None:
    marker_path = state_marker_path()
    digest = clipboard_digest()
    write_marker(marker_path, "none" if digest is None else digest)


def clipboard_changed() -> bool:
    marker_path = state_marker_path()
    before = read_marker(marker_path)
    if not before:
        return False
    digest = clipboard_digest()
    try:
        marker_path.unlink()
    except FileNotFoundError:
        pass
    return digest is not None and before != digest


def hyprland_environment() -> dict[str, str]:
    environment = dict(os.environ)
    if environment.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return environment
    try:
        instances = json.loads(
            subprocess.check_output(["hyprctl", "instances", "-j"], text=True)
        )
        wanted_display = environment.get("WAYLAND_DISPLAY", "")
        selected = next(
            (item for item in instances if item.get("wl_socket") == wanted_display),
            instances[0] if instances else None,
        )
        if selected and selected.get("instance"):
            environment["HYPRLAND_INSTANCE_SIGNATURE"] = selected["instance"]
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, IndexError):
        pass
    return environment


def active_window_is_terminal() -> bool:
    environment = hyprland_environment()
    try:
        raw = subprocess.check_output(
            ["hyprctl", "activewindow", "-j"], text=True, env=environment
        )
        window = json.loads(raw)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return False
    return any(tag.rstrip("*") == "terminal" for tag in window.get("tags", []))


def send_shortcut(mods: str, key: str, state: str) -> None:
    expression = (
        "hl.dsp.send_key_state({"
        f' mods = "{mods}", key = "{key}", state = "{state}"'
        " })"
    )
    subprocess.run(
        ["hyprctl", "dispatch", expression],
        check=False,
        env=hyprland_environment(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> None:
    action = sys.argv[1] if len(sys.argv) > 1 else "paste"
    if action == "snapshot":
        snapshot_clipboard()
        return
    if action != "paste" or not clipboard_changed():
        return
    # This is the same policy as Omarchy's default clipboard.lua:
    # terminals use Shift+Insert; other surfaces use Ctrl+V.
    mods, key = ("SHIFT", "Insert") if active_window_is_terminal() else ("CTRL", "V")
    send_shortcut(mods, key, "down")
    time.sleep(0.05)
    send_shortcut(mods, key, "up")


if __name__ == "__main__":
    main()

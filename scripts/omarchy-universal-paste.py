#!/usr/bin/env python3
"""Paste Voxtype's already-populated clipboard using Omarchy's focus rules."""

from __future__ import annotations

import json
import hashlib
import os
import pathlib
import subprocess
import sys
import time

STATE_DIR = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "voxtype-enhance"
CLIPBOARD_MARKER = STATE_DIR / "clipboard-before.sha256"


def clipboard_text() -> bytes | None:
    try:
        result = subprocess.run(
            ["wl-paste", "--no-newline", "--type", "text/plain"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return None
    if result.returncode != 0 or not result.stdout:
        return None
    return result.stdout


def snapshot_clipboard() -> None:
    content = clipboard_text()
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    marker = "none" if content is None else hashlib.sha256(content).hexdigest()
    CLIPBOARD_MARKER.write_text(marker, encoding="ascii")


def clipboard_changed() -> bool:
    try:
        before = CLIPBOARD_MARKER.read_text(encoding="ascii").strip()
    except OSError:
        return False
    content = clipboard_text()
    after = "none" if content is None else hashlib.sha256(content).hexdigest()
    try:
        CLIPBOARD_MARKER.unlink()
    except FileNotFoundError:
        pass
    return content is not None and before != after


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

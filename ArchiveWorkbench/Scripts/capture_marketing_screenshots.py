#!/usr/bin/env python3
"""Capture welcome / browse light / browse dark / creation screenshots into Assets/screenshots.

Uses the Debug app binary and fictional fixtures only. Requires Screen Recording
permission for screencapture -l. Always launches with -visual-capture so the app
serves fictional recents and never reads/writes real recent prefs.
"""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "build" / "DerivedData" / "Build" / "Products" / "Debug" / "MacUnzip.app"
OUT = ROOT / "Assets" / "screenshots"
BUNDLE_ID = "com.smkzw.MacUnzip"
READY_MARKER = Path("/tmp/macunzip_visual_ready")


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, capture_output=True)


def quit_app() -> None:
    run(["osascript", "-e", f'tell application id "{BUNDLE_ID}" to quit'], check=False)
    time.sleep(0.5)
    run(["killall", "MacUnzip"], check=False)
    time.sleep(0.4)


def launch(args: list[str]) -> None:
    quit_app()
    READY_MARKER.unlink(missing_ok=True)
    binary = APP / "Contents" / "MacOS" / "MacUnzip"
    log_path = Path(f"/tmp/macunzip_capture_launch_{int(time.time())}.log")
    log_file = log_path.open("w")
    proc = subprocess.Popen(
        [str(binary), *args],
        stdout=log_file,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    print(json.dumps({"launch_pid": proc.pid, "log": str(log_path), "args": args}))
    time.sleep(0.8)
    if proc.poll() is not None:
        log_file.flush()
        raise RuntimeError(
            f"MacUnzip exited immediately code={proc.returncode} log={log_path.read_text()[:2000]!r}"
        )


def wait_ready(expected: str, timeout: float = 12.0) -> str:
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        if READY_MARKER.exists():
            last = READY_MARKER.read_text(encoding="utf-8").strip()
            ok = last == expected or last.startswith(expected + ":")
            if ok:
                # Extra settle so SwiftUI commits the branch swap / sheet.
                time.sleep(1.0)
                return last
        if app_pid() is None:
            raise RuntimeError(f"MacUnzip exited before ready marker (last={last!r})")
        time.sleep(0.2)
    raise RuntimeError(f"ready marker timeout expected={expected!r} last={last!r}")


def app_pid() -> int | None:
    result = run(
        [
            "osascript",
            "-e",
            f'tell application "System Events" to get unix id of (first process whose bundle identifier is "{BUNDLE_ID}")',
        ],
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        return int(result.stdout.strip())
    except ValueError:
        return None


def list_windows(pid: int) -> list[dict[str, int | str]]:
    helper = r'''
import AppKit
import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    print("[]"); exit(0)
}
var rows: [[String: Any]] = []
for w in info {
    let ownerPID = w[kCGWindowOwnerPID as String] as? Int32 ?? 0
    guard ownerPID == Int32(pid) else { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = Int((b["Width"] as? NSNumber)?.doubleValue ?? 0)
    let height = Int((b["Height"] as? NSNumber)?.doubleValue ?? 0)
    let x = Int((b["X"] as? NSNumber)?.doubleValue ?? 0)
    let y = Int((b["Y"] as? NSNumber)?.doubleValue ?? 0)
    guard height > 120, width > 200 else { continue }
    rows.append([
        "id": Int((w[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0),
        "name": w[kCGWindowName as String] as? String ?? "",
        "w": width,
        "h": height,
        "x": x,
        "y": y,
        "area": width * height,
        "layer": w[kCGWindowLayer as String] as? Int ?? 0,
    ])
}
let data = try! JSONSerialization.data(withJSONObject: rows)
print(String(data: data, encoding: .utf8)!)
'''
    result = run(["swift", "-e", helper, str(pid)], check=False)
    if result.returncode != 0:
        return []
    try:
        return json.loads(result.stdout.strip() or "[]")
    except json.JSONDecodeError:
        return []


def choose_window(pid: int, mode: str) -> dict[str, int | str] | None:
    windows = list_windows(pid)
    print(json.dumps({"windows": windows, "mode": mode}))
    if not windows:
        return None
    if mode == "creation":
        # Creation fixture is now in-window; accept ~640 height panels.
        panels = [
            w for w in windows
            if int(w["y"]) >= 0 and 560 <= int(w["h"]) <= 720 and 560 <= int(w["w"]) <= 1000
        ]
        if panels:
            panels.sort(key=lambda w: abs(int(w["w"]) - 640) + abs(int(w["h"]) - 640))
            return panels[0]
        raise RuntimeError(f"creation panel window not found in {windows!r}")
    windows.sort(key=lambda w: int(w["area"]), reverse=True)
    return windows[0]


def capture(name: str, mode: str) -> Path:
    dest = OUT / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    last_err = ""
    for _ in range(30):
        pid = app_pid()
        if pid is None:
            time.sleep(0.3)
            continue
        run([
            "osascript", "-e",
            f'''tell application "System Events"
              tell (first process whose bundle identifier is "{BUNDLE_ID}")
                set frontmost to true
              end tell
            end tell'''
        ], check=False)
        time.sleep(0.25)
        chosen = choose_window(pid, mode)
        if not chosen:
            last_err = "no CG window id"
            time.sleep(0.3)
            continue
        wid = int(chosen["id"])
        result = run(["screencapture", "-x", "-l", str(wid), str(dest)], check=False)
        if result.returncode == 0 and dest.exists() and dest.stat().st_size > 20_000:
            print(json.dumps({
                "file": str(dest),
                "window_id": wid,
                "mode": mode,
                "bounds": {
                    "x": int(chosen["x"]),
                    "y": int(chosen["y"]),
                    "w": int(chosen["w"]),
                    "h": int(chosen["h"]),
                },
                "bytes": dest.stat().st_size,
            }))
            return dest
        last_err = result.stderr or "screencapture failed"
        time.sleep(0.3)
    raise RuntimeError(f"window capture unavailable: {last_err}")


def main() -> None:
    if not APP.exists():
        raise SystemExit(f"missing app binary: {APP}")

    common = [
        "-ui-testing",
        "-visual-capture",
        "-AppleLanguages", "(zh-Hans)",
        "-ApplePersistenceIgnoreState", "YES",
        "-NSTreatUnknownArgumentsAsOpen", "NO",
    ]
    shots = [
        (
            "welcome.png",
            "welcome",
            [*common, "-appearance-light"],
        ),
        (
            "media_fixture.png",
            "media",
            [*common, "-appearance-light", "-media-fixture"],
        ),
        (
            "media_dark.png",
            "media",
            [*common, "-appearance-dark", "-media-fixture"],
        ),
        (
            "creation.png",
            "creation",
            [*common, "-appearance-light", "-creation-fixture"],
        ),
    ]

    aliases = {
        "welcome.png": "app_welcome.png",
        "media_fixture.png": "app_media_light.png",
        "media_dark.png": "app_media_dark.png",
    }

    try:
        for name, mode, args in shots:
            launch(args)
            ready = wait_ready(mode)
            print(json.dumps({"ready": ready, "shot": name}))
            path = capture(name, mode)
            if name in aliases:
                alias = OUT / aliases[name]
                alias.write_bytes(path.read_bytes())
                print(json.dumps({"alias": str(alias), "bytes": alias.stat().st_size}))
    finally:
        quit_app()
        READY_MARKER.unlink(missing_ok=True)


if __name__ == "__main__":
    main()

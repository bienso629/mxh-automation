#!/usr/bin/env python3
import os
import sys
import pty
import select
import termios
import tty
import time
import threading
from pathlib import Path

MOBILE_DIR = Path(__file__).parent.resolve()
LIB_DIR = MOBILE_DIR / "lib"

class FileWatcher(threading.Thread):
    def __init__(self, master_fd, debounce_sec=0.8):
        super().__init__(daemon=True)
        self.master_fd = master_fd
        self.debounce_sec = debounce_sec
        self.snapshots = {}
        self._update_snapshots()

    def _get_files(self):
        return list(LIB_DIR.rglob("*.dart")) + [MOBILE_DIR / "pubspec.yaml"]

    def _update_snapshots(self):
        current = {}
        for p in self._get_files():
            try:
                current[p] = p.stat().st_mtime
            except FileNotFoundError:
                pass
        self.snapshots = current

    def run(self):
        last_reload = 0.0
        while True:
            time.sleep(0.5)
            changed = False
            for p in self._get_files():
                try:
                    mtime = p.stat().st_mtime
                    if p not in self.snapshots or mtime > self.snapshots[p]:
                        changed = True
                        break
                except FileNotFoundError:
                    pass

            if changed:
                self._update_snapshots()
                now = time.time()
                if now - last_reload >= self.debounce_sec:
                    last_reload = now
                    try:
                        os.write(self.master_fd, b'r')
                    except OSError:
                        break

def main():
    os.chdir(MOBILE_DIR)
    device_args = sys.argv[1:] if len(sys.argv) > 1 else ["-d", "linux"]
    cmd = ["flutter", "run"] + device_args

    pid, master_fd = pty.fork()

    if pid == 0:
        # Child process: run flutter
        os.execvp(cmd[0], cmd)
    else:
        # Parent process: monitor file changes and forward input/output
        watcher = FileWatcher(master_fd)
        watcher.start()

        old_tty = None
        if sys.stdin.isatty():
            try:
                old_tty = termios.tcgetattr(sys.stdin)
                tty.setraw(sys.stdin.fileno())
            except Exception:
                pass

        try:
            while True:
                r, _, _ = select.select([sys.stdin, master_fd], [], [])
                if sys.stdin in r:
                    data = os.read(sys.stdin.fileno(), 1024)
                    if not data:
                        break
                    os.write(master_fd, data)
                if master_fd in r:
                    try:
                        data = os.read(master_fd, 1024)
                        if not data:
                            break
                        os.write(sys.stdout.fileno(), data)
                    except OSError:
                        break
        finally:
            if old_tty:
                try:
                    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_tty)
                except Exception:
                    pass
            try:
                os.close(master_fd)
            except OSError:
                pass

if __name__ == "__main__":
    main()

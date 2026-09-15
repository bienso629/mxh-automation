import sys
import time
import subprocess
import os

def update_title(avd_name, new_title, pid=None):
    end_time = time.time() + 90
    sanitized_avd = avd_name.lower().replace('-', '_')
    applied = 0

    while time.time() < end_time and applied < 5:
        try:
            res = subprocess.run(['xwininfo', '-root', '-tree'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            lines = res.stdout.splitlines()
            target_win_ids = set()

            for line in lines:
                parts = line.strip().split()
                if not parts or not parts[0].startswith('0x'):
                    continue
                wid = parts[0]

                # Kiểm tra thông tin cửa sổ qua xprop
                prop_res = subprocess.run(['xprop', '-id', wid, '_NET_WM_PID', 'WM_CLASS', 'WM_NAME'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                props = prop_res.stdout

                if 'qemu-system' in props or 'Emulator' in props or 'Android Emulator' in props or 'qemu' in props.lower():
                    is_match = False
                    if pid and f'_NET_WM_PID(CARDINAL) = {pid}' in props:
                        is_match = True
                    else:
                        # Kiểm tra xem có đúng process của AVD này không
                        for pid_line in props.splitlines():
                            if '_NET_WM_PID' in pid_line:
                                try:
                                    wpid = pid_line.split('=')[1].strip()
                                    with open(f'/proc/{wpid}/cmdline', 'r', errors='ignore') as f:
                                        cmd = f.read().lower()
                                        if sanitized_avd in cmd or avd_name.lower() in cmd:
                                            is_match = True
                                        elif pid:
                                            # Kiểm tra xem wpid có phải con của pid launcher không
                                            with open(f'/proc/{wpid}/stat', 'r', errors='ignore') as sf:
                                                ppid = sf.read().split()[3]
                                                if ppid == str(pid):
                                                    is_match = True
                                except Exception:
                                    pass
                    if is_match:
                        target_win_ids.add(wid)

            if target_win_ids:
                for wid in target_win_ids:
                    subprocess.run(['xprop', '-id', wid, '-f', '_NET_WM_NAME', '8u', '-set', '_NET_WM_NAME', new_title], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.run(['xprop', '-id', wid, '-f', 'WM_NAME', '8s', '-set', 'WM_NAME', new_title], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.run(['xprop', '-id', wid, '-f', '_NET_WM_VISIBLE_NAME', '8u', '-set', '_NET_WM_VISIBLE_NAME', new_title], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.run(['xprop', '-id', wid, '-f', '_NET_WM_ICON_NAME', '8u', '-set', '_NET_WM_ICON_NAME', new_title], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.run(['xprop', '-id', wid, '-f', 'WM_ICON_NAME', '8s', '-set', 'WM_ICON_NAME', new_title], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.run(['xprop', '-id', wid, '-f', 'WM_CLASS', '8s', '-set', 'WM_CLASS', new_title], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                applied += 1
        except Exception:
            pass
        time.sleep(2)

if __name__ == '__main__':
    if len(sys.argv) >= 3:
        avd_name = sys.argv[1]
        title = sys.argv[2]
        pid = sys.argv[3] if len(sys.argv) >= 4 else None
        update_title(avd_name, title, pid)

import 'dart:io';
import 'package:path/path.dart' as p;
import 'persona_service.dart';

/// Service tạo và thực thi CLI Automation Tools cho Local CLI Agent (agy, claude, gemini, etc.)
class CliAutomationBridgeService {
  static final CliAutomationBridgeService _instance = CliAutomationBridgeService._internal();
  factory CliAutomationBridgeService() => _instance;
  CliAutomationBridgeService._internal();

  final PersonaService _personaService = PersonaService();

  String get _cliScriptDir {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final dir = p.join(home, '.agent_mxh_auto', 'bin');
    if (!Directory(dir).existsSync()) {
      try {
        Directory(dir).createSync(recursive: true);
      } catch (_) {}
    }
    return dir;
  }

  /// Khởi tạo và ghi file công cụ `mxh-tool` ra thư mục ~/.agent_mxh_auto/bin/mxh-tool
  /// Giúp Local CLI Agent (agy, claude...) có thể trực tiếp chạy lệnh:
  /// `mxh-tool list-profiles`
  /// `mxh-tool open-browser --ip <ip> [--url <url>]`
  /// `mxh-tool close-browser --ip <ip>`
  /// `mxh-tool open-device --ip <ip> [--type mobile|tablet]`
  /// `mxh-tool close-device --ip <ip>`
  Future<String> ensureCliHelperInstalled() async {
    final scriptPath = p.join(_cliScriptDir, 'mxh-tool');
    final scriptFile = File(scriptPath);

    const scriptContent = '''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mxh-tool: Công cụ điều khiển tự động hóa MXH cho Local CLI Agent (Google Antigravity agy, Claude Code...)
Tương tác trực tiếp với API/Socket hoặc file dữ liệu cấu hình của ứng dụng Agent MXH Auto.
"""
import sys
import os
import json
import argparse
import subprocess
import time
import urllib.request

HOME = os.path.expanduser("~")
DATA_DIR = os.path.join(HOME, ".agent_mxh_auto") if os.path.exists(os.path.join(HOME, ".agent_mxh_auto")) else os.path.join(HOME, ".tadu_ai_agent")
PERSONAS_FILE = os.path.join(DATA_DIR, "personas.json")
CONFIG_FILE = os.path.join(DATA_DIR, "config.json")
IPC_SOCKET_PORT = 19898  # Optional IPC port if agent daemon is listening

def list_profiles():
    if not os.path.exists(PERSONAS_FILE):
        print(json.dumps([]))
        return
    try:
        with open(PERSONAS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            profiles = []
            for ip, p in data.items():
                profiles.append({
                    "ip": ip,
                    "name": p.get("name", "Unknown"),
                    "gender": p.get("gender", ""),
                    "age": p.get("age", 25),
                    "bio": p.get("bio", ""),
                    "device_type": p.get("device_type", "mobile"),
                    "avd_name": p.get("avd_name"),
                    "external_device_address": p.get("external_device_address")
                })
            print(json.dumps(profiles, ensure_ascii=False, indent=2))
    except Exception as e:
        print(f"Error reading personas: {e}", file=sys.stderr)
        sys.exit(1)

def _decrypt_vault_value(val):
    if not val or not isinstance(val, str) or not val.startswith("enc:"):
        return val
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.backends import default_backend
        import hashlib, base64

        machine_id = "tadu-cloud-ai-agent-control-center-secret-salt-2026"
        for p in ["/etc/machine-id", "/var/lib/dbus/machine-id"]:
            if os.path.exists(p):
                with open(p, "r", encoding="utf-8") as f:
                    machine_id += f.read().strip()
                break
        key_bytes = hashlib.sha256(machine_id.encode("utf-8")).digest()
        enc_key = key_bytes[16:32]

        raw = base64.urlsafe_b64decode(val[4:] + "===")
        iv = raw[9:25]
        cipher_bytes = raw[25:-32]
        cipher = Cipher(algorithms.AES(enc_key), modes.CBC(iv), backend=default_backend())
        decryptor = cipher.decryptor()
        plain = decryptor.update(cipher_bytes) + decryptor.finalize()
        pad = plain[-1]
        return plain[:-pad].decode("utf-8", errors="ignore")
    except Exception:
        return val

def _get_server_for_ip(target_ip):
    if not os.path.exists(CONFIG_FILE):
        return None
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        servers_raw = _decrypt_vault_value(cfg.get("servers"))
        servers = json.loads(servers_raw) if servers_raw else []
        active_id = _decrypt_vault_value(cfg.get("active_server_id"))

        server_100 = None
        active_server = None
        for s in servers:
            sid = _decrypt_vault_value(s.get("id"))
            sip = _decrypt_vault_value(s.get("server_ip"))
            sname = _decrypt_vault_value(s.get("name"))
            if sname == "Server 100" or sip == "103.74.116.119":
                server_100 = s
            if active_id and (sid == active_id or sip == active_id):
                active_server = s

        chosen = None
        if target_ip.startswith("103.74.") and server_100:
            chosen = server_100
        elif active_server:
            chosen = active_server
        elif server_100:
            chosen = server_100
        elif servers:
            chosen = servers[0]
        else:
            chosen = cfg

        s_ip = _decrypt_vault_value(chosen.get("server_ip"))
        s_port = _decrypt_vault_value(chosen.get("ssh_port")) or 22
        s_user = _decrypt_vault_value(chosen.get("ssh_user")) or "root"
        s_pass = _decrypt_vault_value(chosen.get("ssh_pass")) or ""
        return {
            "server_ip": s_ip,
            "ssh_port": int(s_port),
            "ssh_user": s_user,
            "ssh_pass": s_pass
        }
    except Exception as e:
        return None

def _start_socks5_for_ip(ip):
    server = _get_server_for_ip(ip)
    if not server or not server.get("server_ip") or not server.get("ssh_pass"):
        return None

    # Tìm cổng local trống
    import socket
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    local_port = s.getsockname()[1]
    s.close()

    tmp_dir = os.path.join(DATA_DIR, "tmp")
    os.makedirs(tmp_dir, exist_ok=True)
    askpass_file = os.path.join(tmp_dir, f"ssh_askpass_{ip.replace('.', '_')}_{local_port}.sh")
    escaped_pass = server["ssh_pass"].replace("\\\\", "\\\\\\\\").replace('"', '\\\\"').replace("\$", "\\\\\$")
    with open(askpass_file, "w", encoding="utf-8") as f:
        f.write(f'#!/bin/sh\\necho "{escaped_pass}"\\n')
    os.chmod(askpass_file, 0o700)

    # Tính toán remote socks5 port nếu là Server 100 hoặc alias
    parts = ip.split(".")
    remote_socks_port = None
    if len(parts) == 4:
        try:
            p2, p3 = int(parts[2]), int(parts[3])
            remote_socks_port = 20000 + (p2 * 256 + p3) % 10000
        except Exception:
            pass

    is_alias = (ip != server["server_ip"])
    use_remote_socks = remote_socks_port is not None and (is_alias or server["server_ip"] == "103.74.116.119")
    if use_remote_socks:
        forward_args = ["-L", f"127.0.0.1:{local_port}:127.0.0.1:{remote_socks_port}"]
    else:
        forward_args = ["-D", f"127.0.0.1:{local_port}"]

    ssh_cmd = [
        "ssh",
        "-N",
        *forward_args,
        "-p", str(server["ssh_port"]),
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=3",
        f"{server['ssh_user']}@{server['server_ip']}"
    ]

    env = os.environ.copy()
    env["SSH_ASKPASS"] = askpass_file
    env["SSH_ASKPASS_REQUIRE"] = "force"
    if "DISPLAY" not in env or not env["DISPLAY"]:
        env["DISPLAY"] = ":0"

    try:
        proc = subprocess.Popen(ssh_cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        # Ghi nhận pid và port vào file metadata
        meta_file = os.path.join(tmp_dir, f"socks_{ip.replace('.', '_')}.json")
        with open(meta_file, "w", encoding="utf-8") as f:
            json.dump({"pid": proc.pid, "local_port": local_port, "askpass": askpass_file}, f)

        # Chờ socket lắng nghe (tối đa 6 giây)
        ready = False
        for _ in range(24):
            time.sleep(0.25)
            try:
                test_sock = socket.socket()
                test_sock.settimeout(0.3)
                test_sock.connect(("127.0.0.1", local_port))
                test_sock.close()
                ready = True
                break
            except Exception:
                pass

        if ready:
            print(f"Đã thiết lập hầm SSH SOCKS5 proxy 127.0.0.1:{local_port} cho IP {ip} qua {server['server_ip']}")
            return f"socks5://127.0.0.1:{local_port}"
        else:
            print(f"Không thể kết nối hầm SOCKS5 SSH cho IP {ip}, sẽ mở không proxy.", file=sys.stderr)
            return None
    except Exception as e:
        print(f"Lỗi khởi chạy SSH tunnel cho IP {ip}: {e}", file=sys.stderr)
        return None

def _setup_facebook_vietnamese(profile_dir):
    try:
        ext_dir = os.path.join(profile_dir, "vietnamese_meta_ext")
        os.makedirs(ext_dir, exist_ok=True)
        manifest_file = os.path.join(ext_dir, "manifest.json")
        rules_file = os.path.join(ext_dir, "rules.json")
        if not os.path.exists(manifest_file) or not os.path.exists(rules_file):
            with open(manifest_file, "w", encoding="utf-8") as f:
                json.dump({
                    "manifest_version": 3,
                    "name": "Force Vietnamese Meta",
                    "version": "1.0",
                    "description": "Forces Facebook and Meta to use Vietnamese interface",
                    "permissions": ["declarativeNetRequest"],
                    "host_permissions": ["*://*.facebook.com/*", "*://*.fb.com/*", "*://*.messenger.com/*"],
                    "declarative_net_request": {
                        "rule_resources": [{"id": "ruleset_1", "enabled": True, "path": "rules.json"}]
                    }
                }, f)
            with open(rules_file, "w", encoding="utf-8") as f:
                json.dump([{
                    "id": 1,
                    "priority": 1,
                    "action": {
                        "type": "modifyHeaders",
                        "requestHeaders": [{"header": "Accept-Language", "operation": "set", "value": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7"}]
                    },
                    "condition": {
                        "urlFilter": "*facebook.com*",
                        "resourceTypes": ["main_frame", "sub_frame", "stylesheet", "script", "image", "xmlhttprequest", "other"]
                    }
                }], f)
    except Exception:
        pass

def open_browser(ips, url=None):
    if not ips:
        print("Lỗi: Cần cung cấp ít nhất một địa chỉ IP (--ip hoặc --ips)", file=sys.stderr)
        sys.exit(1)

    url_to_open = url or "https://type.vn"
    for ip in ips:
        sanitized_ip = ip.replace(".", "_").replace(":", "_")
        profile_dir = os.path.join(DATA_DIR, "browser_profiles", f"ip_{sanitized_ip}")
        os.makedirs(profile_dir, exist_ok=True)
        _setup_facebook_vietnamese(profile_dir)

        # 1. Khởi tạo đường hầm SOCKS5 SSH cho IP
        socks5_proxy = _start_socks5_for_ip(ip)

        # 2. Tìm Chrome/Chromium/Brave/Edge trên Linux
        candidates = [
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/bin/chromium-browser",
            "/usr/bin/chromium",
            "/usr/bin/brave-browser",
            "/usr/bin/microsoft-edge"
        ]
        browser_exe = None
        for c in candidates:
            if os.path.exists(c) and os.access(c, os.X_OK):
                browser_exe = c
                break

        if not browser_exe:
            subprocess.Popen(["xdg-open", url_to_open])
            print(f"Đã mở {url_to_open} qua trình duyệt mặc định hệ thống cho IP {ip}")
            continue

        ext_dir = os.path.join(profile_dir, "vietnamese_meta_ext")
        cmd = [
            browser_exe,
            f"--user-data-dir={profile_dir}",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-blink-features=AutomationControlled",
            "--ignore-certificate-errors",
            "--disable-features=Translate,TranslateUI",
            "--disable-translate",
            "--lang=vi",
            "--accept-lang=vi-VN,vi,en-US,en",
            # Ép chạy qua X11 (XWayland) thay vì Wayland native:
            # Wayland native + NVIDIA xung đột Vulkan -> GPU acceleration hỏng -> trang web giật lag.
            "--ozone-platform=x11",
            "--disable-gpu-compositing"
        ]

        if socks5_proxy:
            cmd.append(f"--proxy-server={socks5_proxy}")
        if os.path.exists(ext_dir):
            cmd.append(f"--load-extension={ext_dir}")

        target_url = url_to_open
        if "facebook.com" in target_url and "locale=" not in target_url:
            sep = "&" if "?" in target_url else "?"
            target_url = f"{target_url}{sep}locale=vi_VN"
        cmd.append(target_url)

        env = os.environ.copy()
        if "DISPLAY" not in env or not env["DISPLAY"]:
            env["DISPLAY"] = ":0"
        # Không truyền WAYLAND_DISPLAY cho trình duyệt:
        # Chrome ưu tiên Wayland native nếu thấy biến này, gây lỗi Vulkan trên NVIDIA.
        env.pop("WAYLAND_DISPLAY", None)
        env["LANG"] = "vi_VN.UTF-8"
        env["LANGUAGE"] = "vi_VN:vi"
        env["LC_ALL"] = "vi_VN.UTF-8"

        try:
            subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            proxy_info = f" (qua SOCKS5 SSH: {socks5_proxy})" if socks5_proxy else " (không proxy)"
            print(f"Đã khởi chạy trình duyệt profile cho IP {ip}{proxy_info} tại URL: {target_url}")
            if len(ips) > 1:
                time.sleep(0.3)
        except Exception as e:
            print(f"Không thể mở trình duyệt cho IP {ip}: {e}", file=sys.stderr)

def close_browser(ips):
    tmp_dir = os.path.join(DATA_DIR, "tmp")
    for ip in ips:
        sanitized_ip = ip.replace(".", "_").replace(":", "_")
        needle = f"browser_profiles/ip_{sanitized_ip}"
        try:
            subprocess.run(["pkill", "-f", needle], check=False)
            print(f"Đã gửi tín hiệu đóng trình duyệt cho IP {ip}")
        except Exception as e:
            print(f"Lỗi đóng trình duyệt cho IP {ip}: {e}", file=sys.stderr)

        # Dọn dẹp tiến trình SSH SOCKS5 tương ứng
        meta_file = os.path.join(tmp_dir, f"socks_{sanitized_ip}.json")
        if os.path.exists(meta_file):
            try:
                with open(meta_file, "r", encoding="utf-8") as f:
                    meta = json.load(f)
                pid = meta.get("pid")
                if pid:
                    subprocess.run(["kill", "-9", str(pid)], check=False)
                askpass = meta.get("askpass")
                if askpass and os.path.exists(askpass):
                    os.remove(askpass)
                os.remove(meta_file)
                print(f"Đã dọn dẹp hầm SSH SOCKS5 proxy cho IP {ip}")
            except Exception:
                pass

def open_device(ip, device_type="mobile", avd_name=None):
    sdk_emulator = os.path.expanduser("~/Android/Sdk/emulator/emulator")
    if not os.path.exists(sdk_emulator):
        sdk_emulator = "emulator"

    sdk_adb = os.path.expanduser("~/Android/Sdk/platform-tools/adb")
    if not os.path.exists(sdk_adb):
        sdk_adb = "adb"

    sanitized_ip = ip.replace(".", "_").replace(":", "_")
    target_avd = avd_name
    if not target_avd:
        persona_avd_name = f"Pixel_10_Pro_persona_{sanitized_ip}"
        try:
            res = subprocess.run([sdk_emulator, "-list-avds"], stdout=subprocess.PIPE, text=True, check=False)
            avds = [line.strip() for line in res.stdout.splitlines() if line.strip()]
            if persona_avd_name in avds:
                target_avd = persona_avd_name
            elif avds:
                target_avd = avds[0]
        except Exception:
            pass

    if not target_avd:
        print("Không tìm thấy máy ảo AVD nào trong hệ thống Android SDK!", file=sys.stderr)
        sys.exit(1)

    # 1. Khởi tạo đường hầm SOCKS5 SSH cho IP này
    socks5_proxy = _start_socks5_for_ip(ip)
    socks5_port = None
    if socks5_proxy and ":" in socks5_proxy:
        try:
            socks5_port = int(socks5_proxy.split(":")[-1])
        except Exception:
            socks5_port = None

    # 2. Khởi tạo HTTP Proxy Bridge chuyển tiếp sang SOCKS5
    http_proxy_port = None
    bridge_proc = None
    if socks5_port:
        bridge_script = os.path.expanduser("~/Documents/Projects/Typing/apps/plugins/agent-mxh-auto/lib/core/services/scripts/socks2http_bridge.py")
        if os.path.exists(bridge_script):
            hs = socket.socket()
            hs.bind(("0.0.0.0", 0))
            http_proxy_port = hs.getsockname()[1]
            hs.close()

            try:
                bridge_proc = subprocess.Popen(
                    [sys.executable, bridge_script, str(http_proxy_port), "127.0.0.1", str(socks5_port), "0.0.0.0"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    start_new_session=True
                )
                for _ in range(20):
                    time.sleep(0.1)
                    try:
                        ts = socket.socket()
                        ts.settimeout(0.2)
                        ts.connect(("127.0.0.1", http_proxy_port))
                        ts.close()
                        break
                    except Exception:
                        pass
            except Exception as e:
                print(f"Lỗi khởi động HTTP bridge cho thiết bị: {e}", file=sys.stderr)
                http_proxy_port = None

    # 3. Tìm cổng console khả dụng cho emulator (5554 đến 5584 chẵn)
    console_port = 5554
    for p in range(5554, 5586, 2):
        s1 = socket.socket()
        r1 = s1.connect_ex(("127.0.0.1", p))
        s1.close()
        s2 = socket.socket()
        r2 = s2.connect_ex(("127.0.0.1", p + 1))
        s2.close()
        if r1 != 0 and r2 != 0:
            console_port = p
            break

    cmd = [
        sdk_emulator,
        "-avd", target_avd,
        "-port", str(console_port),
        "-netdelay", "none",
        "-netspeed", "full",
        "-gpu", "host",
        "-no-boot-anim"
    ]
    if http_proxy_port:
        cmd.extend(["-http-proxy", f"http://127.0.0.1:{http_proxy_port}"])
    if device_type == "tablet":
        cmd.extend(["-skin", "1200x1920"])

    env = os.environ.copy()
    if "DISPLAY" not in env or not env["DISPLAY"]:
        env["DISPLAY"] = ":0"

    try:
        emu_proc = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        # Lưu metadata quản lý máy ảo và proxy theo IP
        tmp_dir = os.path.join(DATA_DIR, "tmp")
        os.makedirs(tmp_dir, exist_ok=True)
        dev_meta_file = os.path.join(tmp_dir, f"device_{sanitized_ip}.json")
        with open(dev_meta_file, "w", encoding="utf-8") as f:
            json.dump({
                "ip": ip,
                "target_avd": target_avd,
                "console_port": console_port,
                "emulator_pid": emu_proc.pid,
                "bridge_pid": bridge_proc.pid if bridge_proc else None,
                "http_proxy_port": http_proxy_port,
                "socks5_port": socks5_port
            }, f)

        proxy_str = f"qua SOCKS5 SSH & HTTP Bridge (10.0.2.2:{http_proxy_port})" if http_proxy_port else "không proxy"
        print(f"Đã mở thiết bị Android máy ảo {target_avd} cho IP {ip} [port {console_port}] {proxy_str}")

        # Chạy luồng nền cấu hình proxy và đánh thức AVD qua ADB
        def _bg_adb_setup():
            serial = f"emulator-{console_port}"
            # Chờ boot xong (tối đa 40s)
            for _ in range(20):
                time.sleep(2)
                try:
                    res = subprocess.run([sdk_adb, "-s", serial, "shell", "getprop", "sys.boot_completed"], stdout=subprocess.PIPE, text=True, check=False)
                    if res.stdout.strip() == "1":
                        break
                except Exception:
                    pass
            # Cấu hình adb global proxy
            if http_proxy_port:
                try:
                    subprocess.run([sdk_adb, "-s", serial, "shell", "settings", "put", "global", "http_proxy", f"10.0.2.2:{http_proxy_port}"], check=False)
                except Exception:
                    pass
            # Đánh thức & mở khóa màn hình
            try:
                subprocess.run([sdk_adb, "-s", serial, "shell", "input", "keyevent", "224"], check=False)
                subprocess.run([sdk_adb, "-s", serial, "shell", "input", "keyevent", "82"], check=False)
                subprocess.run([sdk_adb, "-s", serial, "shell", "input", "swipe", "500", "1500", "500", "500", "200"], check=False)
            except Exception:
                pass

        threading.Thread(target=_bg_adb_setup, daemon=True).start()

    except Exception as e:
        print(f"Lỗi khởi chạy máy ảo cho IP {ip}: {e}", file=sys.stderr)

def close_device(ip=None):
    sdk_adb = os.path.expanduser("~/Android/Sdk/platform-tools/adb")
    if not os.path.exists(sdk_adb):
        sdk_adb = "adb"

    tmp_dir = os.path.join(DATA_DIR, "tmp")
    if ip:
        sanitized_ip = ip.replace(".", "_").replace(":", "_")
        dev_meta_file = os.path.join(tmp_dir, f"device_{sanitized_ip}.json")
        console_port = None
        bridge_pid = None
        if os.path.exists(dev_meta_file):
            try:
                with open(dev_meta_file, "r", encoding="utf-8") as f:
                    meta = json.load(f)
                console_port = meta.get("console_port")
                bridge_pid = meta.get("bridge_pid")
                emu_pid = meta.get("emulator_pid")
                if bridge_pid:
                    subprocess.run(["kill", "-9", str(bridge_pid)], check=False)
                if emu_pid:
                    subprocess.run(["kill", str(emu_pid)], check=False)
                os.remove(dev_meta_file)
            except Exception:
                pass

        if console_port:
            serial = f"emulator-{console_port}"
            try:
                subprocess.run([sdk_adb, "-s", serial, "shell", "settings", "put", "global", "http_proxy", ":0"], check=False)
                subprocess.run([sdk_adb, "-s", serial, "emu", "kill"], check=False)
            except Exception:
                pass
        else:
            try:
                subprocess.run([sdk_adb, "emu", "kill"], check=False)
            except Exception:
                pass

        # Dọn dẹp SSH SOCKS5 tương ứng nếu không còn trình duyệt dùng
        meta_file = os.path.join(tmp_dir, f"socks_{sanitized_ip}.json")
        if os.path.exists(meta_file):
            try:
                with open(meta_file, "r", encoding="utf-8") as f:
                    smeta = json.load(f)
                spid = smeta.get("pid")
                if spid:
                    subprocess.run(["kill", "-9", str(spid)], check=False)
                askpass = smeta.get("askpass")
                if askpass and os.path.exists(askpass):
                    os.remove(askpass)
                os.remove(meta_file)
            except Exception:
                pass

        print(f"Đã tắt thiết bị Android máy ảo và dọn dẹp proxy cho IP {ip}.")
    else:
        try:
            subprocess.run([sdk_adb, "emu", "kill"], check=False)
            print("Đã gửi lệnh tắt tất cả thiết bị Android máy ảo.")
        except Exception as e:
            print(f"Lỗi tắt máy ảo: {e}", file=sys.stderr)

def main():
    parser = argparse.ArgumentParser(description="MXH Auto CLI Tool for Local CLI Agents")
    subparsers = parser.add_subparsers(dest="command")

    # list-profiles
    subparsers.add_parser("list-profiles", help="Lấy danh sách các nhân vật nuôi nick (profiles)")

    # open-browser
    p_open = subparsers.add_parser("open-browser", help="Mở trình duyệt riêng cho nhân vật")
    p_open.add_argument("--ip", help="Địa chỉ IP nhân vật")
    p_open.add_argument("--ips", nargs="+", help="Danh sách các IP")
    p_open.add_argument("--url", help="URL cần mở (facebook, tiktok, v.v.)")

    # close-browser
    p_close = subparsers.add_parser("close-browser", help="Đóng trình duyệt nhân vật")
    p_close.add_argument("--ip", help="Địa chỉ IP nhân vật")
    p_close.add_argument("--ips", nargs="+", help="Danh sách các IP")

    # open-device
    p_dev = subparsers.add_parser("open-device", help="Khởi chạy máy ảo Android")
    p_dev.add_argument("--ip", required=True, help="IP nhân vật")
    p_dev.add_argument("--type", default="mobile", help="Loại thiết bị: mobile hoặc tablet")
    p_dev.add_argument("--avd", help="Tên máy ảo AVD")

    # close-device
    p_cdev = subparsers.add_parser("close-device", help="Tắt máy ảo Android")
    p_cdev.add_argument("--ip", help="IP nhân vật")

    args = parser.parse_args()
    if args.command == "list-profiles":
        list_profiles()
    elif args.command == "open-browser":
        ips = []
        if args.ip: ips.append(args.ip)
        if args.ips: ips.extend(args.ips)
        open_browser(ips, args.url)
    elif args.command == "close-browser":
        ips = []
        if args.ip: ips.append(args.ip)
        if args.ips: ips.extend(args.ips)
        close_browser(ips)
    elif args.command == "open-device":
        open_device(args.ip, args.type, args.avd)
    elif args.command == "close-device":
        close_device(args.ip)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
''';

    await scriptFile.writeAsString(scriptContent);
    try {
      await Process.run('chmod', ['+x', scriptPath]);
    } catch (_) {}

    return scriptPath;
  }

  /// Xây dựng Full System Instructions kèm hướng dẫn thực thi công cụ terminal
  /// và thông tin danh sách nhân vật cho Local CLI Agent (agy, claude, gemini...)
  Future<String> buildCliSystemContext({String? workingDir}) async {
    final helperPath = await ensureCliHelperInstalled();
    final personas = await _personaService.loadSavedPersonas();

    final buffer = StringBuffer();
    buffer.writeln('=== QUY TẮC BẮT BUỘC DÀNH CHO LOCAL CLI AI AGENT ===');
    buffer.writeln('Bạn là AI Agent tự động hóa mạng xã hội (MXH) chạy trực tiếp trên máy local của người dùng.');
    buffer.writeln('Bạn có toàn quyền sử dụng terminal để khởi chạy trình duyệt, tương tác với tài khoản và điều khiển thiết bị.');
    buffer.writeln('');
    buffer.writeln('BỘ CÔNG CỤ ĐIỀU KHIỂN ĐƯỢC CẤP SẴN TRÊN MÁY:');
    buffer.writeln('Đường dẫn công cụ helper: `$helperPath` (hoặc lệnh `mxh-tool`)');
    buffer.writeln('1. Mở trình duyệt nuôi nick cho 1 nhân vật:');
    buffer.writeln('   $helperPath open-browser --ip <IP> --url <URL_TRANG_WEB>');
    buffer.writeln('2. Mở trình duyệt đồng loạt cho NHIỀU nhân vật (khi Scope có nhiều nhân vật):');
    buffer.writeln('   $helperPath open-browser --ips <IP1> <IP2> <IP3> ... --url <URL_TRANG_WEB>');
    buffer.writeln('3. Đóng trình duyệt của nhân vật:');
    buffer.writeln('   $helperPath close-browser --ip <IP>');
    buffer.writeln('   $helperPath close-browser --ips <IP1> <IP2> ...');
    buffer.writeln('4. Mở thiết bị máy ảo Android cho nhân vật:');
    buffer.writeln('   $helperPath open-device --ip <IP>');
    buffer.writeln('5. Đóng thiết bị máy ảo Android:');
    buffer.writeln('   $helperPath close-device --ip <IP>');
    buffer.writeln('6. Tra cứu danh sách nhân vật:');
    buffer.writeln('   $helperPath list-profiles');
    buffer.writeln('');

    // Trích xuất các IP trong Scope hiện tại nếu có
    final scopeIps = <String>[];
    if (workingDir != null && workingDir.isNotEmpty) {
      final ipRegex = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
      final matches = ipRegex.allMatches(workingDir);
      for (final m in matches) {
        final ipStr = m.group(0);
        if (ipStr != null && !scopeIps.contains(ipStr)) {
          scopeIps.add(ipStr);
        }
      }
    }

    if (workingDir != null && workingDir.isNotEmpty) {
      buffer.writeln('PHẠM VI (SCOPE) CHỈ ĐỊNH CHO PHIÊN NÀY:');
      buffer.writeln(workingDir);
      buffer.writeln('');
      if (scopeIps.isNotEmpty) {
        buffer.writeln('DANH SÁCH ${scopeIps.length} ĐỊA CHỈ IP ĐƯỢC CHỈ ĐỊNH TRONG SCOPE:');
        buffer.writeln(scopeIps.join(' '));
        buffer.writeln('');
      }
    }

    if (personas.isNotEmpty) {
      buffer.writeln('DANH SÁCH TOÀN BỘ NHÂN VẬT & IP TRÊN HỆ THỐNG:');
      for (final p in personas.values) {
        buffer.writeln('- IP: ${p.ip} | Tên: ${p.name} | Giới tính: ${p.gender} | Tuổi: ${p.age}');
        if (p.bio.isNotEmpty) {
          buffer.writeln('  Tiểu sử: ${p.bio}');
        }
      }
      buffer.writeln('');
    }

    buffer.writeln('QUY TẮC ĐIỀU KHIỂN & MỞ THIẾT BỊ / TRÌNH DUYỆT BẮT BUỘC:');
    buffer.writeln('- TRÌNH DUYỆT & THIẾT BỊ ĐÃ ĐƯỢC ÉP DÙNG PROXY SOCKS5 SSH THEO TỪNG IP:');
    buffer.writeln('  Khi chạy lệnh `open-device --ip <IP>`, hệ thống tự động khởi tạo hầm SOCKS5 SSH, kích hoạt HTTP bridge và cấu hình proxy toàn phần (Android Emulator flag `-http-proxy` và ADB global proxy `10.0.2.2:<port>`). Tất cả lưu lượng mạng của máy ảo đều đi qua IP sạch của nhân vật đó.');
    buffer.writeln('  Khi chạy `close-device --ip <IP>`, hệ thống tự động tắt máy ảo, gỡ proxy và dọn dẹp hầm SSH tương ứng.');
    buffer.writeln('');
    if (scopeIps.length > 1) {
      buffer.writeln('- QUAN TRỌNG: Người dùng đang chọn ${scopeIps.length} nhân vật trong Scope (${scopeIps.join(', ')}).');
      buffer.writeln('- Khi người dùng bảo mở link, xem link, hoặc làm việc chung mà KHÔNG chỉ định đích danh 1 ai: BẮT BUỘC phải mở trình duyệt cho TOÀN BỘ ${scopeIps.length} nhân vật bằng cách truyền toàn bộ danh sách IP vào tham số `--ips`:');
      buffer.writeln('  Lệnh mẫu: $helperPath open-browser --ips ${scopeIps.join(' ')} --url <URL>');
      buffer.writeln('- TUYỆT ĐỐI KHÔNG được chỉ chọn 1 người đầu tiên mà bỏ quên các nhân vật còn lại trong Scope.');
    } else if (scopeIps.length == 1) {
      buffer.writeln('- Scope hiện tại chỉ chọn đúng 1 nhân vật: IP ${scopeIps.first}. BẮT BUỘC chỉ mở 1 trình duyệt cho IP này:');
      buffer.writeln('  Lệnh mẫu: $helperPath open-browser --ip ${scopeIps.first} --url <URL>');
    } else {
      buffer.writeln('- Khi người dùng yêu cầu mở trình duyệt, xem link hoặc auto tương tác, BẮT BUỘC phải chạy lệnh `$helperPath open-browser` bằng terminal.');
    }
    buffer.writeln('- BẮT BUỘC phải thực thi lệnh terminal thực tế để mở cửa sổ trình duyệt trên màn hình người dùng.');
    buffer.writeln('- TUYỆT ĐỐI KHÔNG giải thích vòng vo về headless mode hay khuyên người dùng tự mở lệnh.');
    buffer.writeln('- Sau khi thực thi lệnh, hãy báo cáo chi tiết danh sách tất cả các nhân vật/IP đã được mở trình duyệt thành công.');

    return buffer.toString();
  }
}

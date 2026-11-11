#!/usr/bin/env python3
"""Native application adapter. One bounded JSON request; no service or shell.

GIO owns desktop-entry discovery, precedence, field codes, terminal launching,
DBus activation and desktop actions. Rust owns the Apps workflow/preferences.
Only an explicit launch operation executes a discovered application's data.
"""
import base64
from contextlib import contextmanager
import ctypes as C
import ctypes.util
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import time


class GList(C.Structure):
    pass


GList._fields_ = [("data", C.c_void_p), ("next", C.POINTER(GList)), ("prev", C.POINTER(GList))]


class GError(C.Structure):
    _fields_ = [("domain", C.c_uint), ("code", C.c_int), ("message", C.c_char_p)]


def run(argv, timeout=4, limit=131072):
    result = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            errors="replace", timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip()[:500] or "Native command did not complete")
    return result.stdout[:limit].strip()


def windows(tree):
    """Compositor focus order within each container (not a global timestamp)."""
    if tree.get("app_id") or tree.get("window_properties"):
        yield tree
    children = tree.get("nodes", []) + tree.get("floating_nodes", [])
    order = tree.get("focus", [])
    children.sort(key=lambda n: order.index(n["id"]) if n["id"] in order else len(order))
    for child in children:
        yield from windows(child)


def sway_tree():
    if not os.environ.get("SWAYSOCK") or not shutil.which("swaymsg"):
        raise RuntimeError("Window inspection requires the Sway session")
    # Parsed whole: a cut tree is not JSON, and a busy desktop passes any limit.
    return json.loads(run(["swaymsg", "-r", "-t", "get_tree"], limit=None))


def matching(app, tree):
    # Exact app IDs and the entry's declared X11 class; never title guesses.
    identifiers = {app["id"].removesuffix(".desktop"), app["wm_class"]} - {""}
    return [w for w in windows(tree) if w.get("app_id") in identifiers or
            w.get("window_properties", {}).get("class") in identifiers]


def most_recent(app, tree):
    """Only select an MRU that the compositor tree can establish unambiguously.

    Sway orders siblings, but does not expose global focus timestamps. If two
    nested branches contain matches and the newest branch last focused a
    different app, their matching windows cannot be ordered reliably.
    """
    matches = {w["id"]: w for w in matching(app, tree)}
    def choose(node):
        if node.get("id") in matches:
            return node
        children = node.get("nodes", []) + node.get("floating_nodes", [])
        order = node.get("focus", [])
        children.sort(key=lambda n: order.index(n["id"]) if n["id"] in order else len(order))
        branches = [c for c in children if any(w["id"] in matches for w in windows(c))]
        if not branches:
            return None
        if len(branches) == 1:
            return choose(branches[0])
        # Home is the focused window whenever it asks, so it orders nothing.
        latest = next((w for w in windows(branches[0]) if w.get("app_id") != "spark-dialog"), None)
        if latest and latest["id"] in matches:
            return latest
        raise RuntimeError("Cannot reliably order matching windows in separate groups; choose a window in Workspace or use Application default")
    return choose(tree)


@contextmanager
def launch_stdio():
    # Desktop children must not inherit the host's JSON pipes. Keep the adapter's
    # descriptors for its receipt, and let the application outlive the helper.
    saved = [os.dup(fd) for fd in (0, 1, 2)]
    try:
        with open(os.devnull, "r+b", buffering=0) as null:
            for fd in (0, 1, 2):
                os.dup2(null.fileno(), fd)
            yield
    finally:
        for fd, copy in enumerate(saved):
            os.dup2(copy, fd)
            os.close(copy)


# GLib's known terminal list (gdesktopappinfo.c). A private xterm -e bridge
# covers foot-only desktops, including GLib versions predating xdg-terminal-exec.
TERMINALS = ("xdg-terminal-exec", "kgx", "gnome-terminal", "mate-terminal", "xfce4-terminal",
             "tilix", "konsole", "nxterm", "color-xterm", "rxvt", "dtterm", "xterm")


def foot_fallback():
    return bool(shutil.which("foot") and not any(shutil.which(t) for t in TERMINALS))


class Desktop:
    def __init__(self):
        name = ctypes.util.find_library("gio-2.0")
        if not name:
            raise RuntimeError("Application discovery needs the system GLib/GIO library")
        self.gio = C.CDLL(name)
        self.glib = C.CDLL(ctypes.util.find_library("glib-2.0"))
        self.gobject = C.CDLL(ctypes.util.find_library("gobject-2.0"))
        ptr, string, integer = C.c_void_p, C.c_char_p, C.c_int
        signatures = {
            "g_app_info_get_all": (C.POINTER(GList), []),
            "g_app_info_get_id": (string, [ptr]),
            "g_app_info_get_display_name": (string, [ptr]),
            "g_app_info_get_name": (string, [ptr]),
            "g_app_info_get_description": (string, [ptr]),
            "g_app_info_get_executable": (string, [ptr]),
            "g_app_info_get_commandline": (string, [ptr]),
            "g_app_info_should_show": (integer, [ptr]),
            "g_desktop_app_info_new": (ptr, [string]),
            "g_desktop_app_info_get_filename": (string, [ptr]),
            "g_desktop_app_info_get_generic_name": (string, [ptr]),
            "g_desktop_app_info_get_categories": (string, [ptr]),
            "g_desktop_app_info_get_startup_wm_class": (string, [ptr]),
            "g_desktop_app_info_get_string": (ptr, [ptr, string]),
            "g_desktop_app_info_get_boolean": (integer, [ptr, string]),
            "g_desktop_app_info_list_actions": (C.POINTER(string), [ptr]),
            "g_desktop_app_info_launch_action": (None, [ptr, string, ptr]),
            "g_app_launch_context_new": (ptr, []),
            "g_app_info_launch": (integer, [ptr, ptr, ptr, C.POINTER(C.POINTER(GError))]),
        }
        for symbol, (result, args) in signatures.items():
            fn = getattr(self.gio, symbol)
            fn.restype, fn.argtypes = result, args
        self.glib.g_free.argtypes = [ptr]
        self.glib.g_list_free.argtypes = [C.POINTER(GList)]
        self.glib.g_error_free.argtypes = [C.POINTER(GError)]
        self.gobject.g_object_unref.argtypes = [ptr]

    @staticmethod
    def text(value):
        return value.decode("utf-8", "replace") if value else ""

    def string(self, info, key):
        value = self.gio.g_desktop_app_info_get_string(info, key.encode())
        if not value:
            return ""
        try:
            return self.text(C.cast(value, C.c_char_p).value)
        finally:
            self.glib.g_free(value)

    def record(self, info):
        g = self.gio
        actions, i = [], 0
        array = g.g_desktop_app_info_list_actions(info)
        while array and array[i]:
            actions.append(self.text(array[i]))
            i += 1
        ident = self.text(g.g_app_info_get_id(info))
        wm_class = self.text(g.g_desktop_app_info_get_startup_wm_class(info))
        terminal = bool(g.g_desktop_app_info_get_boolean(info, b"Terminal"))
        return {"id": ident, "name": self.text(g.g_app_info_get_name(info)),
                "display_name": self.text(g.g_app_info_get_display_name(info)),
                "description": self.text(g.g_app_info_get_description(info)),
                "generic_name": self.text(g.g_desktop_app_info_get_generic_name(info)),
                "categories": self.text(g.g_desktop_app_info_get_categories(info)).strip(";").split(";"),
                "launcher": self.text(g.g_desktop_app_info_get_filename(info)),
                "wm_class": wm_class,
                "focus": bool(os.environ.get("SWAYSOCK") and (wm_class or ident.count(".") >= 3 or terminal and foot_fallback())),
                "new_window": next((a for a in actions if a.lower().replace("-", "").replace("_", "") == "newwindow"), "")}

    def catalog(self, icon_px=None):
        head = self.gio.g_app_info_get_all()
        node, apps, seen = head, [], set()
        # with a size asked (#230), each app's icon drawn at it into the cache, within the catalog's time for icons
        index = icon_index() if icon_px else {}
        cache, deadline = icon_cache(), time.monotonic() + ICON_BUDGET
        try:
            while node:
                info = node.contents.data
                ident = self.text(self.gio.g_app_info_get_id(info))
                # GIO can also return non-desktop AppInfo implementations.
                entry = self.gio.g_desktop_app_info_new(ident.encode()) if ident else None
                try:
                    if entry and self.gio.g_app_info_should_show(entry) and ident not in seen:
                        app = self.record(entry)
                        if icon_px:
                            source = icon_source(self.string(entry, "Icon").strip(), icon_px, index)
                            drawn = draw_icon(source, icon_px, cache, deadline) if source else None
                            if drawn:
                                app["icon"] = str(drawn)
                        apps.append(app)
                        seen.add(ident)
                finally:
                    if entry:
                        self.gobject.g_object_unref(entry)
                    self.gobject.g_object_unref(info)
                node = node.contents.next
        finally:
            self.glib.g_list_free(head)
        # the name as the desktop entry writes it, in its spelling; the order by it whatever its case
        return {"apps": sorted(apps, key=lambda a: (a["name"].lower(), a["id"])), "source": "System desktop entries (GIO)"}

    def entry(self, ident):
        if not isinstance(ident, str) or not ident.endswith(".desktop") or "/" in ident or any(ord(c) < 32 or ord(c) == 127 for c in ident):
            raise ValueError("Invalid application identity")
        info = self.gio.g_desktop_app_info_new(ident.encode())
        if not info or not self.gio.g_app_info_should_show(info):
            if info:
                self.gobject.g_object_unref(info)
            raise RuntimeError("This application is no longer available; refresh Apps")
        return info

    def details(self, ident):
        info = self.entry(ident)
        try:
            app = self.record(info)
            launcher = app["launcher"]
            executable = self.text(self.gio.g_app_info_get_executable(info))
            command = self.string(info, "Exec")
            try:
                # Display only. GIO, not this parser, interprets Exec on launch.
                arguments = " ".join(shlex.split(command)[1:]) or "None declared"
            except ValueError:
                arguments = "See the original command below"
            user_data = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
            scope = "User" if Path(launcher).is_relative_to(user_data) else "System"
            package = package_details(launcher)
            fields = [["Identity", ident], ["Package", package.get("package", "Unavailable")],
                      ["Executable", shutil.which(executable) or executable or "Unavailable"],
                      ["Arguments", arguments], ["Command", command or "Not declared (may use DBus activation)"],
                      ["Launcher", launcher], ["Metadata source", "Desktop entry via GIO; package data from " + package.get("source", "unavailable package manager")],
                      ["Terminal", "Yes" if self.gio.g_desktop_app_info_get_boolean(info, b"Terminal") else "No"],
                      ["DBus activation", "Declared" if self.gio.g_desktop_app_info_get_boolean(info, b"DBusActivatable") else "Not declared"],
                      ["Window class", app["wm_class"] or "Not declared"],
                      ["File types", self.string(info, "MimeType") or "Not declared"],
                      ["Access", "Not declared by desktop entries; this does not imply a sandbox or unrestricted access"]]
            flatpak = self.string(info, "X-Flatpak")
            if flatpak and re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_-]+){2,}", flatpak) and shutil.which("flatpak"):
                try:
                    permissions = run(["flatpak", "info", "--show-permissions", flatpak])
                    fields.append(["Declared access", permissions or "No permissions reported by Flatpak"])
                    fields.append(["Access source", "Flatpak installed metadata; application behavior is not inferred"])
                    package["source"] = "Flatpak"
                except (RuntimeError, subprocess.TimeoutExpired):
                    fields.append(["Declared access", "Flatpak metadata unavailable"])
            try:
                opened = matching(app, sway_tree())
                fields.append(["Running windows", "\n".join(str(w.get("name") or "Untitled") for w in opened) or "None"])
                fields.append(["Processes", ", ".join(str(w["pid"]) for w in opened if w.get("pid")) or "None reported by Sway"])
            except (RuntimeError, OSError, subprocess.TimeoutExpired, ValueError):
                fields.append(["Running windows", "Unavailable outside a supported Sway session"])
            return {"id": ident, "version": package.get("version", "Unavailable"),
                    "installed": package.get("source", "Unavailable") + " / " + scope,
                    "source": package.get("source", "Desktop entry; package metadata unavailable"), "fields": fields}
        finally:
            self.gobject.g_object_unref(info)

    def launch(self, ident, mode):
        info = self.entry(ident)  # Revalidate the identity immediately before execution.
        context = None
        try:
            app = self.record(info)
            before = []
            try:
                before = matching(app, sway_tree())
            except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired):
                if mode == "focus":
                    raise RuntimeError("Focus existing requires a working Sway session")
            if mode == "focus":
                if not app["focus"]:
                    raise RuntimeError("This app does not declare a reliable window identity")
                if before:
                    recent = most_recent(app, sway_tree())
                    if recent is None:  # the last matching window closed during inspection
                        return self.launch(ident, "default")
                    target = int(recent["id"])
                    reply = json.loads(run(["swaymsg", "-r", "[con_id=%d] focus" % target]))
                    if not all(r.get("success") for r in reply):
                        raise RuntimeError("The compositor could not focus this window")
                    if not any(w["id"] == target and w.get("focused") for w in windows(sway_tree())):
                        raise RuntimeError("Focus was requested, but could not be confirmed")
                    return {"message": app["name"].lower() + " focused", "confirmed": True}
            elif mode not in ("default", "new"):
                raise ValueError("Unknown launch preference")
            if self.gio.g_desktop_app_info_get_boolean(info, b"Terminal") and foot_fallback():
                os.environ["PATH"] = str(Path(__file__).resolve().parent / "apps-terminal") + os.pathsep + os.environ["PATH"]
                os.environ["SPARK_APPS_TERMINAL_ID"] = ident.removesuffix(".desktop")
            context = self.gio.g_app_launch_context_new()
            with launch_stdio():
                if mode == "new":
                    if not app["new_window"]:
                        raise RuntimeError("This app does not declare a New window action")
                    # Standard desktop actions own their execution semantics.
                    self.gio.g_desktop_app_info_launch_action(info, app["new_window"].encode(), context)
                else:
                    error = C.POINTER(GError)()
                    if not self.gio.g_app_info_launch(info, None, context, C.byref(error)):
                        message = self.text(error.contents.message) if error else "The desktop launcher refused this request"
                        if error:
                            self.glib.g_error_free(error)
                        raise RuntimeError(message)
            previous = {w["id"] for w in before}
            deadline = time.monotonic() + 1.5
            while os.environ.get("SWAYSOCK") and time.monotonic() < deadline:
                try:
                    opened = matching(app, sway_tree())
                    if any(w["id"] not in previous for w in opened):
                        return {"message": app["name"].lower() + " opened", "confirmed": True}
                    if mode != "new" and any(w.get("focused") for w in opened):
                        return {"message": app["name"].lower() + " focused", "confirmed": True}
                except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired):
                    break
                time.sleep(.1)
            return {"message": app["name"].lower() + " started; no window of its own seen yet", "confirmed": False}
        finally:
            if context:
                self.gobject.g_object_unref(context)
            self.gobject.g_object_unref(info)


ICON_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,127}")
ICON_MAX = 8 << 20          # bytes a source icon may be
ICON_BUDGET = 3.0           # seconds a catalog may spend drawing icons; the rest are drawn at the next read
ICON_EXTENSIONS = (".png", ".svg")


def icon_cache():
    """Where drawn icons are kept (#230), one folder a size: the state's, the dialog's to read and no one else's."""
    base = os.environ.get("XDG_STATE_HOME") or ""
    if not os.path.isabs(base):
        base = str(Path.home() / ".local/state")
    return Path(base) / "spark-shell/icons"


def icon_index():
    """Every icon file the themes and pixmaps hold, by name: [(theme rank, size, path)]. hicolor is the theme every
    app installs into and ranks first; another theme's icon is used only where hicolor has none, and pixmaps last."""
    data_home = os.environ.get("XDG_DATA_HOME") or ""
    if not os.path.isabs(data_home):
        data_home = str(Path.home() / ".local/share")
    bases = [data_home] + [d for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if os.path.isabs(d)]
    index = {}
    for base in bases:
        icons = Path(base) / "icons"
        themes = sorted(icons.iterdir()) if icons.is_dir() else []
        for theme in themes:
            rank = 0 if theme.name == "hicolor" else 1
            sizes = sorted(theme.iterdir()) if theme.is_dir() else []
            for size_dir in sizes:
                size = 4096 if size_dir.name == "scalable" else (int(size_dir.name.split("x")[0]) if size_dir.name.split("x")[0].isdigit() else 0)
                folder = size_dir / "apps"
                if not size or not folder.is_dir():
                    continue
                for name in os.listdir(folder):
                    stem, ext = os.path.splitext(name)
                    if ext in ICON_EXTENSIONS:
                        index.setdefault(stem, []).append((rank, size, folder / name))
        pixmaps = Path(base) / "pixmaps"
        if pixmaps.is_dir():
            for name in os.listdir(pixmaps):
                stem, ext = os.path.splitext(name)
                if ext in ICON_EXTENSIONS:
                    index.setdefault(stem, []).append((2, 4096 if ext == ".svg" else 0, pixmaps / name))
    return index


def icon_file(path):
    """A path that is an icon to draw: a regular PNG or SVG file, a link followed, of 8 MB at most."""
    try:
        real = Path(os.path.realpath(path))
        st = real.stat()
    except (OSError, ValueError):
        return None
    if real.suffix.lower() not in ICON_EXTENSIONS or not stat.S_ISREG(st.st_mode) or st.st_size > ICON_MAX:
        return None
    return real


def icon_source(icon, px, index):
    """The file an entry's Icon key names (#230): an absolute path to a PNG or SVG, or a theme name. Of a name's
    files, the best theme first, then the smallest PNG at least the size asked, else a drawing, else the largest."""
    if not icon:
        return None
    if icon.startswith("/"):
        return icon_file(icon)
    if not ICON_NAME.fullmatch(icon):
        return None
    found = index.get(icon) or index.get(os.path.splitext(icon)[0]) or []
    if not found:
        return None
    best_rank = min(rank for rank, _, _ in found)
    files = [(size, path) for rank, size, path in found if rank == best_rank]
    big = sorted((size, str(path)) for size, path in files if size >= px and size < 4096 and path.suffix == ".png")
    drawings = [str(path) for size, path in files if path.suffix == ".svg"]
    pick = big[0][1] if big else (drawings[0] if drawings else max(files, key=lambda f: f[0])[1])
    return icon_file(pick)


def draw_icon(source, px, cache, deadline):
    """The icon drawn at px by px into the cache (#230), once for its file, its time and the size: its path, or
    None when it cannot be drawn or the catalog's time for icons is spent. rsvg-convert draws an SVG, and a PNG
    laid in one, so every icon comes out the same size; nothing is drawn but by it."""
    try:
        st = source.stat()
    except OSError:
        return None
    key = hashlib.sha256(("%s\0%d\0%d\0%d" % (source, st.st_mtime_ns, st.st_size, px)).encode()).hexdigest()[:32]
    folder = cache / str(px)
    out = folder / (key + ".png")
    if out.is_file():
        return out
    if time.monotonic() >= deadline or not shutil.which("rsvg-convert"):
        return None
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    for d in (cache.parent, cache, folder):
        try:
            os.chmod(d, 0o700)
        except OSError:
            pass
    tmp = folder / (".%s.%d" % (key, os.getpid()))
    try:
        if source.suffix.lower() == ".svg":
            drawing = source
        else:
            data = source.read_bytes()
            if not data.startswith(b"\x89PNG\r\n\x1a\n"):
                return None
            drawing = folder / (".%s.%d.svg" % (key, os.getpid()))
            drawing.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><image width="%d" height="%d" '
                               'preserveAspectRatio="xMidYMid meet" href="data:image/png;base64,%s"/></svg>'
                               % (px, px, px, px, base64.b64encode(data).decode()))
        left = max(0.1, min(2.0, deadline - time.monotonic()))
        made = subprocess.run(["rsvg-convert", "--keep-aspect-ratio", "-w", str(px), "-h", str(px), "-o", str(tmp), str(drawing)],
                              stdin=subprocess.DEVNULL, capture_output=True, timeout=left, check=False)
        if made.returncode or not tmp.is_file() or not tmp.read_bytes().startswith(b"\x89PNG"):
            return None
        os.replace(tmp, out)
        return out
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    finally:
        for leftover in (tmp, folder / (".%s.%d.svg" % (key, os.getpid()))):
            try:
                leftover.unlink()
            except OSError:
                pass


def package_details(launcher):
    """Read package metadata on demand; never run an application's --version."""
    try:
        if shutil.which("xbps-query"):
            owner = run(["xbps-query", "-o", launcher]).split(":", 1)[0]
            if owner and re.fullmatch(r"[A-Za-z0-9_.+_-]+", owner):
                pkg = run(["xbps-query", "-p", "pkgver", owner])
                return {"package": pkg, "version": pkg.rsplit("-", 1)[-1], "source": "XBPS"}
        elif shutil.which("dpkg-query"):
            owner = run(["dpkg-query", "-S", launcher]).split(": ", 1)[0].split(", ")[0]
            if re.fullmatch(r"[A-Za-z0-9_.+:-]+", owner):
                version = run(["dpkg-query", "-W", "-f=${Version}", owner])
                return {"package": owner, "version": version, "source": "Debian packages"}
        elif shutil.which("rpm"):
            text = run(["rpm", "-qf", "--qf", "%{NAME}\n%{VERSION}-%{RELEASE}", launcher]).splitlines()
            return {"package": text[0], "version": text[1], "source": "RPM"}
        elif shutil.which("pacman"):
            text = run(["pacman", "-Qo", launcher])
            match = re.search(r" is owned by (\S+) (\S+)$", text)
            if match:
                return {"package": match[1], "version": match[2], "source": "Pacman"}
    except (RuntimeError, OSError, subprocess.TimeoutExpired, IndexError):
        pass
    return {}


def request(data):
    if not isinstance(data, dict):
        raise ValueError("Application request must be an object")
    if data.get("op") == "copy":
        text = data.get("text")
        if not isinstance(text, str) or len(text) > 1048576:
            raise ValueError("that is too much to copy")
        if not shutil.which("wl-copy") or not os.environ.get("WAYLAND_DISPLAY"):
            raise RuntimeError("copying needs wl-copy in a Wayland session")
        copied = subprocess.run(["wl-copy", "--"], input=text, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True, timeout=4)
        if copied.returncode:
            raise RuntimeError("the clipboard did not take it")
        return {"copied": True}
    desktop = Desktop()
    op = data.get("op")
    if op == "catalog":
        px = data.get("icon_px")
        if px is not None and (not isinstance(px, int) or isinstance(px, bool) or not 8 <= px <= 256):
            raise ValueError("an icon's size is 8 to 256 pixels")
        return desktop.catalog(px)
    if op == "details":
        return desktop.details(data.get("id"))
    if op == "launch":
        return desktop.launch(data.get("id"), data.get("mode", "default"))
    raise ValueError("Unknown application operation")


if __name__ == "__main__":
    try:
        raw = sys.stdin.read(65537)
        if len(raw) > 65536:
            raise ValueError("Application request is too large")
        result = request(json.loads(raw))
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        result = {"error": str(error)[:1000]}
    print(json.dumps(result, ensure_ascii=True))

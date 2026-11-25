#!/usr/bin/env python3
"""pin_image.py IMAGE DIR -- IMAGE (NAME:TAG@sha256:DIGEST) from Docker Hub into DIR/root, for test/pin.sh.
pin_image.py --crates CACHE LOCK... -- each crate the LOCKs name is in CACHE, the bytes they name.

Anonymous, over https: the image is asked for by its digest, every manifest, config and layer is held to its own sha256,
and nothing of it is unpacked before it matches. A layer is unpacked in bwrap with DIR's new root alone to write to, so
no name or link in it reaches the machine. Nothing in it runs here: test/pin.sh runs it in bwrap.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

TYPES = ",".join(("application/vnd.oci.image.index.v1+json", "application/vnd.oci.image.manifest.v1+json",
                  "application/vnd.docker.distribution.manifest.list.v2+json", "application/vnd.docker.distribution.manifest.v2+json"))


class NoTokenPastTheHub(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith("https://"):
            raise SystemExit("pin: the hub sent a redirect that is not https")
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new:
            new.remove_header("Authorization")
        return new


def sha256(file):
    h = hashlib.sha256()
    with open(str(file), "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def unpack(layer, root):
    """In bwrap, as --unpack: what the layer takes away of the ones under it, then its files."""
    root = Path(root)
    with tarfile.open(str(layer)) as t:
        names = t.getnames()
    for n in names:
        base, at = os.path.basename(n), root / os.path.dirname(n).lstrip("/")
        gone = list(at.glob("*")) if base == ".wh..wh..opq" else [at / base[4:]] if base.startswith(".wh.") else []
        for g in gone:
            if g.is_dir() and not g.is_symlink():
                shutil.rmtree(str(g))
            elif g.is_symlink() or g.exists():
                g.unlink()
    subprocess.run(["tar", "-xf", str(layer), "-C", str(root), "--exclude=.wh.*", "--exclude=dev/*", "--no-same-owner", "--no-same-permissions"], check=True)


def crates(cache, locks):
    """Every locked crate from a registry is in the cache with the checksum the lock names."""
    bad = 0
    for lock in locks:
        for part in Path(lock).read_text().split("[[package]]")[1:]:
            got = dict(re.findall(r'^(name|version|checksum) = "([^"]*)"$', part, re.M))
            if "checksum" not in got:
                continue
            file = next(iter(Path(cache).glob("*/%s-%s.crate" % (got["name"], got["version"]))), None)
            if not file:
                print("pin: %s %s is not on disk: cargo fetch --locked brings it" % (got["name"], got["version"]), file=sys.stderr)
                bad += 1
            elif sha256(file) != got["checksum"]:
                print("pin: %s is not the crate the lock names" % file.name, file=sys.stderr)
                bad += 1
    return 1 if bad else 0


def fetch(image, where):
    name, digest = image.split("@", 1)
    repo = "library/" + name.split(":", 1)[0]
    web = urllib.request.build_opener(NoTokenPastTheHub)
    token = json.load(web.open("https://auth.docker.io/token?service=registry.docker.io&scope=repository:%s:pull" % repo, timeout=30))["token"]

    def get(kind, which):
        return web.open(urllib.request.Request("https://registry-1.docker.io/v2/%s/%s/%s" % (repo, kind, which),
                                               headers={"Authorization": "Bearer " + token, "Accept": TYPES}), timeout=60)

    def read(kind, which):
        body = get(kind, which).read()
        if "sha256:" + hashlib.sha256(body).hexdigest() != which:
            raise SystemExit("pin: %s is not what the hub sent" % which)
        return json.loads(body)

    (where / "image").unlink(missing_ok=True)   # no image here until the whole of one is
    top = read("manifests", digest)
    if "manifests" in top:
        top = read("manifests", next(m["digest"] for m in top["manifests"] if m["platform"]["architecture"] == "amd64" and m["platform"]["os"] == "linux"))
    read("blobs", top["config"]["digest"])
    files = []
    for layer in top["layers"]:
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", layer["digest"]):
            raise SystemExit("pin: a layer is named by no digest")
        file = where / layer["digest"].split(":")[1]
        if not file.exists() or "sha256:" + sha256(file) != layer["digest"]:
            h, part = hashlib.sha256(), file.with_suffix(".part")
            with get("blobs", layer["digest"]) as r, open(str(part), "wb") as f:
                for block in iter(lambda: r.read(1 << 20), b""):
                    h.update(block)
                    f.write(block)
            if "sha256:" + h.hexdigest() != layer["digest"]:
                part.unlink()
                raise SystemExit("pin: a layer is not its digest")
            part.rename(file)
        print("pin: layer %s, %d MiB, as its digest says" % (layer["digest"][7:19], layer["size"] >> 20), flush=True)
        files.append(file)
    new, root = where / "root.new", where / "root"
    shutil.rmtree(str(new), ignore_errors=True)
    new.mkdir()
    for file in files:
        subprocess.run(["bwrap", "--die-with-parent", "--new-session", "--unshare-all", "--ro-bind", "/usr", "/usr", "--symlink", "usr/bin", "/bin",
                        "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib64", "/lib64", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
                        "--ro-bind", os.path.abspath(__file__), "/unpack.py", "--ro-bind", str(file), "/layer", "--bind", str(new), "/new",
                        "--clearenv", "--setenv", "PATH", "/usr/bin:/usr/sbin", "python3", "-I", "/unpack.py", "--unpack", "/layer", "/new"], check=True)
    shutil.rmtree(str(root), ignore_errors=True)
    new.rename(root)
    (where / "image").write_text(image + "\n")
    print("pin: the image is in %s" % root)
    return 0


if __name__ == "__main__":
    if sys.argv[1] == "--unpack":
        sys.exit(unpack(sys.argv[2], sys.argv[3]))
    if sys.argv[1] == "--crates":
        sys.exit(crates(sys.argv[2], sys.argv[3:]))
    sys.exit(fetch(sys.argv[1], Path(sys.argv[2])))

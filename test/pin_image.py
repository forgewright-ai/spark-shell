#!/usr/bin/env python3
"""pin_image.py IMAGE DIR -- IMAGE (NAME:TAG@sha256:DIGEST) from Docker Hub into DIR/root, for test/pin.sh.

Anonymous, over https: the image is asked for by its digest, every manifest, config and layer is held to its own sha256,
and nothing of it is unpacked before it matches. Nothing in it runs here: test/pin.sh runs it in bwrap.
"""
import hashlib
import json
import os
from pathlib import Path
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


def main():
    image, where = sys.argv[1], Path(sys.argv[2])
    name, digest = image.split("@", 1)
    repo = "library/" + name.split(":", 1)[0]
    where.mkdir(parents=True, exist_ok=True)
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

    top = read("manifests", digest)
    if "manifests" in top:
        top = read("manifests", next(m["digest"] for m in top["manifests"] if m["platform"]["architecture"] == "amd64" and m["platform"]["os"] == "linux"))
    read("blobs", top["config"]["digest"])
    files = []
    for layer in top["layers"]:
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
    root = where / "root"
    shutil.rmtree(str(root), ignore_errors=True)
    root.mkdir()
    for file in files:
        with tarfile.open(str(file)) as t:
            names = t.getnames()
        for n in names:   # what this layer takes away of the ones under it
            base, at = os.path.basename(n), root / os.path.dirname(n)
            gone = list(at.glob("*")) if base == ".wh..wh..opq" else [at / base[4:]] if base.startswith(".wh.") else []
            for g in gone:
                if g.is_dir() and not g.is_symlink():
                    shutil.rmtree(str(g))
                elif g.is_symlink() or g.exists():
                    g.unlink()
        subprocess.run(["tar", "-xf", str(file), "-C", str(root), "--exclude=.wh.*", "--exclude=dev/*", "--no-same-owner", "--no-same-permissions"], check=True)
    (where / "image").write_text(image + "\n")
    print("pin: the image is in %s" % root)


if __name__ == "__main__":
    main()

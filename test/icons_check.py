#!/usr/bin/env python3
"""The bar's icons in step: component/bar/src/icons.rs is what the drawings in component/bar/icons.py give,
or this fails, and with it the build.

    python3 -I test/icons_check.py
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

if __name__ == "__main__":
    sys.exit(subprocess.call([sys.executable, "-I", os.path.join(REPO, "component", "bar", "icons.py"), "--check"]))

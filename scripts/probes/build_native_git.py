#!/usr/bin/env python3
"""Build the pinned libgit2 iOS feasibility probe, outside shipping targets."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = "1.9.7"
SOURCE_SHA256 = "1a4fbe7589e814777ae76b64734ad80f4ecad22cd33a22682a2aaea4ae5375e7"


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=["simulator", "device"], default="simulator")
    parser.add_argument("--output", type=Path, default=ROOT / "build/git-20261028")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"libgit2-v{VERSION}.tar.gz"
    url = f"https://github.com/libgit2/libgit2/archive/refs/tags/v{VERSION}.tar.gz"
    if not archive.exists():
        partial = archive.with_suffix(".partial")
        run("curl", "--fail", "--silent", "--show-error", "--location", url, "-o", partial)
        assert hashlib.sha256(partial.read_bytes()).hexdigest() == SOURCE_SHA256
        partial.replace(archive)
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == SOURCE_SHA256, "Unpinned Git source"
    source = output / f"libgit2-{VERSION}"
    with tarfile.open(archive) as package:
        members = []
        for item in package.getmembers():
            path = output / item.name
            assert path.resolve().is_relative_to(output), "Unsafe source archive path"
            # Upstream has one symlink fixture for its disabled test suite.
            # It is not needed to build the library and is never materialized.
            if item.issym() and item.name == f"libgit2-{VERSION}/tests/resources/testrepo-worktree/link_to_new.txt":
                continue
            assert item.isfile() or item.isdir(), "Unexpected source archive link"
            members.append(item)
        if not source.exists():
            package.extractall(output, members=members, filter="data")
        for item in members:
            if item.isfile():
                path = output / item.name
                assert not path.is_symlink() and path.read_bytes() == package.extractfile(item).read(), "Modified cached Git source: " + item.name
    sdk = "iphonesimulator" if args.platform == "simulator" else "iphoneos"
    build = output / args.platform
    run("cmake", "-S", source, "-B", build, "-DCMAKE_SYSTEM_NAME=iOS",
        f"-DCMAKE_OSX_SYSROOT={sdk}", "-DCMAKE_OSX_ARCHITECTURES=arm64",
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=18.0", "-DBUILD_SHARED_LIBS=OFF",
        "-DBUILD_TESTS=OFF", "-DBUILD_CLI=OFF", "-DUSE_SSH=OFF",
        "-DUSE_HTTPS=SecureTransport", "-DREGEX_BACKEND=builtin", "-DUSE_NSEC=ON")
    run("cmake", "--build", build, "-j", "4")
    library = build / "libgit2.a"
    record = {"libgit2": VERSION, "sourceURL": url, "sourceSHA256": SOURCE_SHA256,
              "platform": args.platform, "minimumIOS": "18.0", "architecture": "arm64",
              "https": "SecureTransport", "ssh": False, "shippingAppLinked": False,
              "archiveSHA256": hashlib.sha256(library.read_bytes()).hexdigest()}
    (build / "crabrix-provenance.json").write_text(json.dumps(record, indent=2) + "\n")
    if args.platform == "simulator":
        run("xcrun", "--sdk", sdk, "clang", "-Werror", "-arch", "arm64",
            "-mios-simulator-version-min=18.0", "-I", source / "include",
            ROOT / "scripts/probes/native-git.c", library,
            "-framework", "Security", "-framework", "CoreFoundation", "-lz", "-liconv",
            "-o", output / "native-git-probe")


if __name__ == "__main__":
    main()

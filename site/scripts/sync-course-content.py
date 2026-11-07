#!/usr/bin/env python3
"""Pin the public Crabrix CoursePack authoring corpus for the free web Learn pages."""

import argparse
import json
import shutil
import struct
import zipfile
import subprocess
from pathlib import Path


SITE = Path(__file__).resolve().parents[1]
COURSE_IDS = ("basics", "ownership", "projects", "concurrency", "interview", "systems", "algorithms")


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="checkout of sergii-ziborov/crabrix-courses")
    args = parser.parse_args()
    source = args.source.resolve()
    if not (source / "CONTENT-LICENSE.md").is_file():
        parser.error("source is not the Crabrix course repository")

    companion = source / "courses/projects/projects/route-git-review/companion"
    if companion.is_dir():
        destination = SITE / "public/examples/task-ledger-route.zip"
        destination.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(companion.rglob("*")):
                if not path.is_file():
                    continue
                info = zipfile.ZipInfo(path.relative_to(companion).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes())

    courses = []
    for course_id in COURSE_IDS:
        folder = source / "courses" / course_id
        course = read_json(folder / "course.json")
        units = []
        for unit_id in course["unitIDs"]:
            unit = read_json(folder / "units" / f"{unit_id}.json")
            lessons = [read_json(folder / "lessons" / f"{lesson_id}.json")
                       for lesson_id in unit["lessonIDs"]]
            if any(lesson["parentID"] != unit_id for lesson in lessons):
                raise ValueError(f"lesson parent mismatch in {course_id}/{unit_id}")
            for lesson in lessons:
                project = folder / 'projects' / lesson['id']
                for resource in lesson.get('resources', []):
                    if resource.get('url') == 'https://crabrix.com/examples/task-ledger-route.zip':
                        resource['url'] = '/examples/task-ledger-route.zip'

                if course_id == 'projects' and lesson['id'] in {
                    'public-api-compatibility', 'msrv-verification', 'feature-compatibility-matrix'
                }:
                    # Complete worked programs, qualified in the local WASM engine.
                    # The separate grading solution/harness is not exported.
                    files = {'main.rs': lesson['writing']['exampleCode']}
                    if lesson['id'] == 'feature-compatibility-matrix':
                        files['Cargo.toml'] = ('[package]\nname="feature-compatibility-matrix"\n'
                            'version="0.1.0"\nedition="2021"\n[features]\n'
                            'default=["details","trace"]\ndetails=[]\ntrace=[]\n')
                    lesson['playgroundProject'] = {
                        'schemaVersion': 1, 'name': lesson['id'], 'entryFile': 'main.rs',
                        'edition': '2021', 'files': files,
                    }
                if course_id == 'projects' and lesson['id'].startswith('route-'):
                    # Readings are complete std-only demonstrations. SQL readings
                    # print their statement; native private labs execute SQLite.
                    lesson['playgroundProject'] = {
                        'schemaVersion': 1, 'name': lesson['id'], 'entryFile': 'main.rs',
                        'edition': '2024', 'files': {'main.rs': lesson['writing']['exampleCode']},
                    }
                # Only the explicitly qualified Cargo demonstrations launch in
                # Playground. Grading harnesses/checks are never exported here.
                if lesson['id'] in {'serde-roundtrip-validation', 'joinset-task-ownership',
                                    'semaphore-backpressure', 'graceful-shutdown-protocol', 'async-runtime'}:
                    metadata = read_json(project / 'project.json')
                    names = ['Cargo.toml', 'Cargo.lock', 'src/main.rs']
                    lesson['playgroundProject'] = {
                        'schemaVersion': 1, 'name': metadata['name'],
                        'entryFile': metadata['entryFile'], 'edition': '2024',
                        'files': {name: (project / name).read_text(encoding='utf-8') for name in names},
                    }
                illustration = lesson.get("illustration")
                if illustration is None:
                    continue
                expected = illustration.get("path")
                allowed = {f"media/{lesson['id']}.png"}
                if course_id == "algorithms":
                    allowed.update({f"media/{unit_id}-{variant}.png" for variant in ("a", "b")})
                if expected not in allowed or not illustration.get("alt"):
                    raise ValueError(f"invalid lesson illustration in {course_id}/{lesson['id']}")
                source_image = folder / expected
                if not source_image.is_file():
                    raise ValueError(f"missing lesson illustration: {source_image}")
                with source_image.open('rb') as image:
                    header = image.read(24)
                if header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
                    raise ValueError(f"invalid PNG dimensions: {source_image}")
                width, height = struct.unpack('>II', header[16:24])
                if not width or not height:
                    raise ValueError(f"empty lesson illustration: {source_image}")
                illustration.update(width=width, height=height)
                destination_image = SITE / "content" / "learn-media" / course_id / Path(expected).name
                destination_image.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source_image, destination_image)
            units.append({**unit, "lessons": lessons})
        courses.append({**course, "units": units})

    courses.sort(key=lambda course: course["order"])
    counts = {course["id"]: sum(len(unit["lessons"]) for unit in course["units"])
              for course in courses}
    if counts["algorithms"] != 600 or any(count <= 0 for count in counts.values()):
        raise ValueError(f"unexpected lesson counts: {counts}")
    commit = subprocess.check_output(("git", "-C", str(source), "rev-parse", "HEAD"), text=True).strip()
    payload = {
        "source": "https://github.com/sergii-ziborov/crabrix-courses",
        "sourceCommit": commit,
        "courseCount": len(courses),
        "lessonCount": sum(counts.values()),
        "rustLessonCount": sum(counts.values()) - counts["algorithms"],
        "courses": courses,
    }
    destination = SITE / "content" / "courses.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{destination}: {len(courses)} courses, {payload['lessonCount']} lessons, source {commit}")


if __name__ == "__main__":
    main()

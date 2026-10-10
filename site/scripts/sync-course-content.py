#!/usr/bin/env python3
"""Pin the public Crabrix CoursePack authoring corpus for the free web Learn pages."""

import argparse
import json
import shutil
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
                destination_image = SITE / "content" / "learn-media" / course_id / Path(expected).name
                destination_image.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source_image, destination_image)
            units.append({**unit, "lessons": lessons})
        courses.append({**course, "units": units})

    courses.sort(key=lambda course: course["order"])
    counts = {course["id"]: sum(len(unit["lessons"]) for unit in course["units"])
              for course in courses}
    if sum(counts.values()) != 742 or counts["algorithms"] != 600:
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

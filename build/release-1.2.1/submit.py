"""Create App Store version 1.2.1, attach the TestFlight build, set What's New and the review notes, submit.
Release stays MANUAL: the owner releases after approval. Owner's word: "Отправляй на ревью" (2026-11-25).
Usage: python3 submit.py <buildNumber> [--dry-run]"""
import sys, json, time
from pathlib import Path
sys.path.insert(0, '/Users/serhiirihgt/dev/crabrix-poc/build/keyboard-testflight-20261031')
from asc import api

VERSION = '1.2.1'
build_number = sys.argv[1]
dry = '--dry-run' in sys.argv
out = Path(__file__).parent
docs = Path('/Users/serhiirihgt/dev/crabrix-poc/docs/app-store')
whats_new = (docs / f'whats-new-{VERSION}.txt').read_text().strip()
notes = (docs / f'review-notes-{VERSION}-build{build_number}.txt').read_text().strip()
assert len(whats_new) <= 4000 and len(notes) <= 4000
save = lambda name, value: (out / f'submit-{name}.json').write_text(json.dumps(value, indent=1))

app = api('apps?filter[bundleId]=com.sergiiziborov.Crabrix')['data'][0]['id']
builds = api(f'builds?filter[app]={app}&filter[version]={build_number}&filter[preReleaseVersion.version]={VERSION}')['data']
assert len(builds) == 1, builds
build = builds[0]
assert build['attributes']['processingState'] == 'VALID', build['attributes']
print('build', build_number, build['id'])

versions = api(f'apps/{app}/appStoreVersions?limit=10')['data']
print('versions', [(v['attributes']['versionString'], v['attributes']['appStoreState']) for v in versions])
live = next(v for v in versions if v['attributes']['appStoreState'] == 'READY_FOR_SALE')
version = next((v for v in versions if v['attributes']['versionString'] == VERSION), None)
open_submissions = [s for s in api(f'reviewSubmissions?filter[app]={app}&limit=20')['data']
                    if s['attributes'].get('state') in ('WAITING_FOR_REVIEW', 'READY_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES')]
print('open submissions', [(s['id'], s['attributes']['state']) for s in open_submissions])
if dry:
    print('dry run: would', 'reuse' if version else 'create', VERSION, 'with build', build_number); raise SystemExit
assert not open_submissions, 'another submission is open'

if not version:
    version = api('appStoreVersions', 'POST', {'data': {'type': 'appStoreVersions',
        'attributes': {'platform': 'IOS', 'versionString': VERSION, 'releaseType': 'MANUAL'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': app}}}}})['data']
    print('created version', version['id'])
else:
    api(f"appStoreVersions/{version['id']}", 'PATCH', {'data': {'type': 'appStoreVersions', 'id': version['id'],
        'attributes': {'releaseType': 'MANUAL'}}})
api(f"appStoreVersions/{version['id']}/relationships/build", 'PATCH', {'data': {'type': 'builds', 'id': build['id']}})
print('build attached')

for loc in api(f"appStoreVersions/{version['id']}/appStoreVersionLocalizations")['data']:
    api(f"appStoreVersionLocalizations/{loc['id']}", 'PATCH', {'data': {'type': 'appStoreVersionLocalizations', 'id': loc['id'],
        'attributes': {'whatsNew': whats_new}}})
    print('whatsNew set for', loc['attributes']['locale'])

previous = api(f"appStoreVersions/{live['id']}/appStoreReviewDetail")['data']['attributes']
contact = {k: previous[k] for k in ('contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail')}
attributes = {**contact, 'notes': notes, 'demoAccountRequired': False}
try:
    detail = api(f"appStoreVersions/{version['id']}/appStoreReviewDetail").get('data')
except Exception:
    detail = None
if detail:
    api(f"appStoreReviewDetails/{detail['id']}", 'PATCH', {'data': {'type': 'appStoreReviewDetails', 'id': detail['id'], 'attributes': attributes}})
else:
    detail = api('appStoreReviewDetails', 'POST', {'data': {'type': 'appStoreReviewDetails', 'attributes': attributes,
        'relationships': {'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version['id']}}}}})['data']
save('review-detail', {'id': detail['id'], 'notesLength': len(notes)})
print('review notes set')

submission = api('reviewSubmissions', 'POST', {'data': {'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
    'relationships': {'app': {'data': {'type': 'apps', 'id': app}}}}})['data']
save('created', submission)
item = api('reviewSubmissionItems', 'POST', {'data': {'type': 'reviewSubmissionItems',
    'relationships': {'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': submission['id']}},
                      'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version['id']}}}}})['data']
save('item', item)
submitted = api(f"reviewSubmissions/{submission['id']}", 'PATCH', {'data': {'type': 'reviewSubmissions', 'id': submission['id'],
    'attributes': {'submitted': True}}})['data']
save('submitted', submitted)
time.sleep(5)
state = api(f"appStoreVersions/{version['id']}")['data']['attributes']
save('readback', state)
attached = api(f"appStoreVersions/{version['id']}/build")['data']['attributes']['version']
print('SUBMITTED', submission['id'], submitted['attributes'].get('state'), state['versionString'], state['appStoreState'], state['releaseType'], 'build', attached)

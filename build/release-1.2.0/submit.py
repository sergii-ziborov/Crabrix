"""Replace 1.1.9 in App Review with 1.2.0: cancel the 1.1.9 review submission, rename that App Store
version to 1.2.0, attach the TestFlight build, set What's New and the review notes, submit.
Release stays MANUAL: the owner releases after approval.
Usage: python3 submit.py <buildNumber> [--dry-run]"""
import sys, json, time
from pathlib import Path
sys.path.insert(0, '/Users/serhiirihgt/dev/crabrix-poc/build/keyboard-testflight-20261031')
from asc import api

build_number = sys.argv[1]
dry = '--dry-run' in sys.argv
out = Path(__file__).parent
docs = Path('/Users/serhiirihgt/dev/crabrix-poc/docs/app-store')
whats_new = (docs / 'whats-new-1.2.0.txt').read_text().strip()
notes = (docs / f'review-notes-1.2.0-build{build_number}.txt').read_text().strip()
assert len(whats_new) <= 4000 and len(notes) <= 4000
save = lambda name, value: (out / f'submit-{name}.json').write_text(json.dumps(value, indent=1))
now = lambda: time.strftime('%H:%M:%S')

app = api('apps?filter[bundleId]=com.sergiiziborov.Crabrix')['data'][0]['id']
builds = api(f'builds?filter[app]={app}&filter[version]={build_number}&filter[preReleaseVersion.version]=1.2.0')['data']
assert len(builds) == 1, builds
build = builds[0]
assert build['attributes']['processingState'] == 'VALID', build['attributes']
print('build', build_number, build['id'])

versions = api(f'apps/{app}/appStoreVersions?limit=10')['data']
states = {v['attributes']['versionString']: v['attributes']['appStoreState'] for v in versions}
print('versions', states)
version = next((v for v in versions if v['attributes']['versionString'] in ('1.2.0', '1.1.9')
                and v['attributes']['appStoreState'] not in ('READY_FOR_SALE', 'REPLACED_WITH_NEW_VERSION', 'REMOVED_FROM_SALE')), None)
assert version, 'no 1.1.9/1.2.0 version in flight'
submissions = [s for s in api(f'reviewSubmissions?filter[app]={app}&limit=20')['data']
               if s['attributes'].get('state') in ('WAITING_FOR_REVIEW', 'READY_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES')]
print('open submissions', [(s['id'], s['attributes']['state']) for s in submissions])
if dry:
    print('dry run: would cancel', [s['id'] for s in submissions], 'rename', version['attributes']['versionString'], '-> 1.2.0'); raise SystemExit

for s in submissions:
    if s['attributes']['state'] == 'IN_REVIEW':
        raise SystemExit('1.1.9 is already in review; not cancelling automatically')
    api(f"reviewSubmissions/{s['id']}", 'PATCH', {'data': {'type': 'reviewSubmissions', 'id': s['id'], 'attributes': {'canceled': True}}})
    print(now(), 'cancel requested', s['id'])
for _ in range(60):
    state = api(f"appStoreVersions/{version['id']}")['data']['attributes']['appStoreState']
    print(now(), 'version state', state, flush=True)
    if state in ('DEVELOPER_REJECTED', 'PREPARE_FOR_SUBMISSION', 'REJECTED', 'METADATA_REJECTED'): break
    time.sleep(10)
else: raise SystemExit('version did not become editable')

api(f"appStoreVersions/{version['id']}", 'PATCH', {'data': {'type': 'appStoreVersions', 'id': version['id'],
    'attributes': {'versionString': '1.2.0', 'releaseType': 'MANUAL'}}})
api(f"appStoreVersions/{version['id']}/relationships/build", 'PATCH', {'data': {'type': 'builds', 'id': build['id']}})
print(now(), 'version 1.2.0 with build', build_number)

for loc in api(f"appStoreVersions/{version['id']}/appStoreVersionLocalizations")['data']:
    if loc['attributes']['locale'] == 'en-US':
        api(f"appStoreVersionLocalizations/{loc['id']}", 'PATCH', {'data': {'type': 'appStoreVersionLocalizations', 'id': loc['id'],
            'attributes': {'whatsNew': whats_new}}})
        print('whatsNew set for', loc['attributes']['locale'])
detail = api(f"appStoreVersions/{version['id']}/appStoreReviewDetail")['data']
api(f"appStoreReviewDetails/{detail['id']}", 'PATCH', {'data': {'type': 'appStoreReviewDetails', 'id': detail['id'],
    'attributes': {'notes': notes, 'demoAccountRequired': False}}})
save('review-detail', {'id': detail['id'], 'notesLength': len(notes)})

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

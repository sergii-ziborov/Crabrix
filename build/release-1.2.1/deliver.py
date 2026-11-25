"""Start Xcode Cloud for Crabrix 1.2.1 on a pushed branch, wait for TestFlight, attach notes and the internal group.
Never submits for review: that needs the owner's word."""
import sys, time, datetime
from pathlib import Path
sys.path.insert(0, '/Users/serhiirihgt/dev/crabrix-poc/build/keyboard-testflight-20261031')
from asc import api

workflow = 'ff6eebeb-2000-4dd8-a1d9-3b4d2598689a'; repository = 'd74a72b4-ffcf-481f-9965-90683b1e0b4e'
branch, sha = sys.argv[1], sys.argv[2]
group = '8e1c1fc1-d1c9-4828-b7a5-a78f72dad871'
notes = Path('/Users/serhiirihgt/dev/crabrix-poc/docs/app-store/testflight-what-to-test-1.2.1.txt').read_text()
now = lambda: datetime.datetime.now(datetime.timezone.utc).strftime('%H:%M:%S')

reference = None
for _ in range(20):
    for item in api(f'scmRepositories/{repository}/gitReferences?limit=200')['data']:
        if item['attributes']['name'] == branch and item['attributes']['kind'] == 'BRANCH': reference = item
    if reference: break
    time.sleep(15)
assert reference, 'branch not visible to Xcode Cloud'
run = api('ciBuildRuns', 'POST', {'data': {'type': 'ciBuildRuns', 'attributes': {'clean': True}, 'relationships': {
    'workflow': {'data': {'type': 'ciWorkflows', 'id': workflow}},
    'sourceBranchOrTag': {'data': {'type': 'scmGitReferences', 'id': reference['id']}}}}})['data']
print(now(), 'started run', run['id'], run['attributes']['number'], flush=True)
while True:
    a = api('ciBuildRuns/' + run['id'])['data']['attributes']
    print(now(), 'run', a['number'], a['executionProgress'], a.get('completionStatus'), flush=True)
    if a['executionProgress'] == 'COMPLETE': break
    time.sleep(60)
for x in api('ciBuildRuns/' + run['id'] + '/actions')['data']: print(x['attributes']['name'], x['attributes']['actionType'], x['attributes']['completionStatus'], flush=True)
if a['completionStatus'] != 'SUCCEEDED': raise SystemExit('Cloud run failed')
assert a['sourceCommit']['commitSha'] == sha, a['sourceCommit']
for _ in range(40):
    linked = api('ciBuildRuns/' + run['id'] + '/builds')['data']
    if linked: break
    time.sleep(30)
assert len(linked) == 1, 'no linked build'
build = linked[0]['id']
for _ in range(120):
    b = api('builds/' + build)['data']['attributes']; print(now(), 'build', b['version'], b['processingState'], flush=True)
    if b['processingState'] == 'VALID': break
    assert b['processingState'] not in ('INVALID', 'FAILED'), b
    time.sleep(30)
else: raise SystemExit('Apple processing timeout')
assert api('builds/' + build + '/preReleaseVersion')['data']['attributes']['version'] == '1.2.1'
assert b.get('usesNonExemptEncryption') is False, 'inspect encryption declaration'
locs = api('builds/' + build + '/betaBuildLocalizations')['data']; en = next((x for x in locs if x['attributes']['locale'] == 'en-US'), None)
if en: api('betaBuildLocalizations/' + en['id'], 'PATCH', {'data': {'type': 'betaBuildLocalizations', 'id': en['id'], 'attributes': {'whatsNew': notes}}})
else: api('betaBuildLocalizations', 'POST', {'data': {'type': 'betaBuildLocalizations', 'attributes': {'locale': 'en-US', 'whatsNew': notes}, 'relationships': {'build': {'data': {'type': 'builds', 'id': build}}}}})
if not any(x['id'] == build for x in api('betaGroups/' + group + '/builds?limit=200')['data']):
    api('betaGroups/' + group + '/relationships/builds', 'POST', {'data': [{'type': 'builds', 'id': build}]})
for _ in range(40):
    state = api('builds/' + build + '/buildBetaDetail')['data']['attributes']['internalBuildState']; print(now(), 'beta', state, flush=True)
    if state == 'IN_BETA_TESTING': break
    time.sleep(15)
else: raise SystemExit('TestFlight group not ready')
print('App Store versions unchanged:', [(v['attributes']['versionString'], v['attributes']['appStoreState']) for v in api('apps/6809502653/appStoreVersions?limit=2')['data']], flush=True)
print('TESTFLIGHT READY', build, b['version'], flush=True)

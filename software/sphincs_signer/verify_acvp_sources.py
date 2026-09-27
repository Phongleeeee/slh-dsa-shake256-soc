"""Verify cached ACVP fixtures against Git blob IDs at the pinned NIST tag.
Fetches only public repository metadata; never uploads local files or keys.
"""
import hashlib
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSION = 'v1.1.0.40'
BASE = ROOT / f'third_party/slhdsa-c/test/.acvp-data/{VERSION}/files'
request = urllib.request.Request(
    f'https://api.github.com/repos/usnistgov/ACVP-Server/git/trees/{VERSION}?recursive=1',
    headers={'User-Agent':'SLH-DSA-project-public-fixture-review'})
with urllib.request.urlopen(request,timeout=60) as response:
    tree = json.load(response)
if tree.get('truncated'):
    raise RuntimeError('NIST tree listing truncated; cannot verify source identity')
entries = {item['path']:item for item in tree['tree']}
rows = []
for path in sorted(BASE.rglob('*.json')):
    relative = path.relative_to(BASE).as_posix()
    if not relative.startswith(('SLH-DSA-keyGen-FIPS205/','SLH-DSA-sigGen-FIPS205/','SLH-DSA-sigVer-FIPS205/')):
        continue
    data = path.read_bytes()
    actual = hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()
    expected = entries['gen-val/json-files/'+relative]['sha']
    if actual != expected:
        raise AssertionError(f'Cached vector differs from NIST {VERSION}: {relative}')
    rows.append({'path':relative,'bytes':len(data),'git_blob':actual,
                 'sha256':hashlib.sha256(data).hexdigest()})
    print(f'NIST FIXTURE MATCH: {relative}',flush=True)
if len(rows) != 7:
    raise AssertionError(f'Expected seven fixture files, got {len(rows)}')
out = ROOT / 'hardware/soc/output_portable/review_acvp_provenance.json'
out.write_text(json.dumps({'repository':'usnistgov/ACVP-Server','tag':VERSION,
                          'tree':tree['sha'],'files':rows},indent=2)+'\n',encoding='utf-8')
print('NIST FIXTURE PROVENANCE PASSED: 7/7 match the pinned public tag',flush=True)

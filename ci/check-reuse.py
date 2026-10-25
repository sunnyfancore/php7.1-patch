"""Fail closed if anything that could affect a compiled RPM changed."""
import subprocess
import sys

old = sys.argv[1]
changed = subprocess.check_output(['git', 'diff', '--name-only', old, 'HEAD'], text=True).splitlines()
allowed = {
    'README.md', 'install.sh', 'packaging/install-rpms.sh', 'packaging/RELEASE-NOTES.md',
    'packaging/PROVENANCE.md', 'ci/verify-patch.php', 'ci/fpm-fixture.php', 'ci/fpm-test.conf',
    'ci/allocator-probe.c', 'ci/check-reuse.py',
}
blocked = [p for p in changed if p not in allowed and not p.startswith(('.github/', 'ci/test-', 'docs/'))]
if blocked:
    raise SystemExit('Rebuild required; compiled input changed:\n' + '\n'.join(blocked))
print('PASS: all source, SAPI, build-system and RPM packaging inputs unchanged')

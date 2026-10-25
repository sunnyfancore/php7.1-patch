#!/usr/bin/env python3
"""Run the same request regressions through the actual Apache PHP module."""
import http.client
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('fpm_tests', Path(__file__).with_name('test-fpm.py'))
fpm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fpm)


def request(fields=(), upload=False, query='', extra_headers=False):
    boundary, body = fpm.multipart(fields, upload, extra_headers)
    conn = http.client.HTTPConnection('127.0.0.1', 9072, timeout=20)
    try:
        page = {'startup_oom=1': 'startup-fixture.php', 'ini_diagnostic=1': 'ini-fixture.php'}.get(query, 'fpm-fixture.php')
        conn.request('POST', '/' + page + '?' + query, body, {
            'Content-Type': 'multipart/form-data; boundary=' + boundary,
            'Cookie': 'PHPSESSID=php71cvetest',
        })
        result = conn.getresponse()
        return json.loads(result.read())
    finally:
        conn.close()


fpm.exercise(request, 'Apache mod_php')

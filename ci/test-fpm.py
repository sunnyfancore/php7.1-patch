#!/usr/bin/env python3
"""Exercise mitigation behavior through a persistent FPM worker."""
import json
import os
import socket
import struct
import time


def record(kind, data=b''):
    return struct.pack('!BBHHBB', 1, kind, 1, len(data), 0, 0) + data


def size(value):
    return bytes([value]) if value < 128 else struct.pack('!I', value | 0x80000000)


def receive(sock, length):
    data = b''
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            raise RuntimeError('FPM closed the connection before completing a response')
        data += chunk
    return data


def multipart(fields=(), upload=False, extra_headers=False):
    boundary = 'php71CveRegressionBoundary'
    chunks = []
    for key, value in fields:
        chunks.append(('--' + boundary + '\r\nContent-Disposition: form-data; name="' + key
                       + '"\r\n' + ('Content-Disposition: form-data; name="ignored"\r\nX-Ignored: test\r\n' if extra_headers else '') + '\r\n' + value + '\r\n').encode())
    if upload:
        chunks.append(('--' + boundary + '\r\nContent-Disposition: form-data; name="upload"; '
                       'filename="probe.txt"\r\nContent-Type: text/plain\r\n\r\n'
                       + 'x' * 4096 + '\r\n').encode())
    chunks.append(('--' + boundary + '--\r\n').encode())
    body = b''.join(chunks)
    return boundary, body


def request(fields=(), upload=False, query='', extra_headers=False):
    boundary, body = multipart(fields, upload, extra_headers)
    params = {
        'GATEWAY_INTERFACE': 'CGI/1.1', 'SERVER_PROTOCOL': 'HTTP/1.1',
        'REQUEST_METHOD': 'POST', 'SCRIPT_FILENAME': '/src/ci/fpm-fixture.php',
        'SCRIPT_NAME': '/fpm-fixture.php', 'REQUEST_URI': '/fpm-fixture.php?' + query,
        'QUERY_STRING': query, 'CONTENT_TYPE': 'multipart/form-data; boundary=' + boundary,
        'CONTENT_LENGTH': str(len(body)), 'SERVER_NAME': 'localhost', 'SERVER_PORT': '80',
        'REMOTE_ADDR': '127.0.0.1', 'HTTP_COOKIE': 'PHPSESSID=php71cvetest',
    }
    encoded = b''
    for key, value in params.items():
        key, value = key.encode(), value.encode()
        encoded += size(len(key)) + size(len(value)) + key + value
    output, errors = b'', b''
    with socket.create_connection(('127.0.0.1', int(os.environ.get('FPM_TEST_PORT', '9071'))), timeout=5) as sock:
        sock.settimeout(20)
        sock.sendall(record(1, struct.pack('!HB5x', 1, 0)) + record(4, encoded)
                     + record(4) + record(5, body) + record(5))
        while True:
            version, kind, request_id, length, padding, _ = struct.unpack('!BBHHBB', receive(sock, 8))
            content = receive(sock, length)
            if padding:
                receive(sock, padding)
            if kind == 6:
                output += content
            elif kind == 7:
                errors += content
            elif kind == 3:
                break
    if b'\r\n\r\n' not in output:
        raise RuntimeError('No complete FastCGI output: ' + repr(output) + repr(errors))
    return json.loads(output.split(b'\r\n\r\n', 1)[1])


def exercise(request, transport):
    deadline = time.monotonic() + 360
    while True:
        try:
            result = request([('ready', '1')])
            break
        except (OSError, RuntimeError):
            if time.monotonic() > deadline:
                raise
            time.sleep(1)
    pid = result['pid']
    for index in range(30):
        result = request([('first', str(index)), ('second', '2'), ('third', '3')])
        assert result['pid'] == pid, result
        assert result['keys'] == ['first', 'second'], result
        assert result['post']['first'] == str(index), result
        assert result['patch'] == 'CVE-2026-109618+CVE-2026-109619;r2', result
        assert result['build'] == os.environ['SOURCE_COMMIT'], result
    print('PASS ' + transport + ': multipart cap, build identity and 30 sequential requests on the same worker')
    result = request([('PHP_SESSION_UPLOAD_PROGRESS', 'probe')], upload=True)
    assert result['file'] is True and result['progress'] is False, result
    print('PASS ' + transport + ': ordinary file upload works; session progress stays disabled even when INI enables it')
    result = request([('original', 'kept')], extra_headers=True)
    assert result['post'] == {'original': 'kept'}, result
    print('PASS ' + transport + ': duplicate/unused multipart headers are ignored')
    for index in range(10):
        result = request(query='handlers=1')
        result = request([('after_cleanup', 'ok')])
        assert result['pid'] == pid and result['post'] == {'after_cleanup': 'ok'}, result
    print('PASS ' + transport + ': repeated fatal handler cleanup and subsequent requests')
    try:
        request(query='oom=1')
    except (OSError, RuntimeError, json.JSONDecodeError):
        pass
    else:
        raise AssertionError('OOM request unexpectedly completed normally')
    result = request([('after_oom', 'ok')])
    assert result['pid'] != pid and result['post'] == {'after_oom': 'ok'}, result
    assert result['patch'] == 'CVE-2026-109618+CVE-2026-109619;r2'
    print('PASS ' + transport + ': OOM worker exits; master replaces it and subsequent requests succeed')


if __name__ == '__main__':
    exercise(request, 'FPM')

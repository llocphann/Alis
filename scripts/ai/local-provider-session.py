#!/usr/bin/env python3
"""One-shot host HTTP text transport, verifying local weights before a prompt."""
import json
import os
import re
import sys
import urllib.error
import urllib.request
from local_provider import LocalProviderError, client, headers, origin, verify, verify_reasoning_off


def main():
    try:
        raw = sys.stdin.buffer.readline(128*1024+1)
        if len(raw) > 128*1024:
            raise LocalProviderError('request_too_large')
        body = json.loads(raw)
        endpoint = os.environ.get('AI_ENDPOINT', '')
        model = os.environ.get('AI_LOCAL_MODEL', '')
        key = os.environ.get('AI_LOCAL_KEY', '')
        origin(endpoint)
        if not isinstance(body, dict) or body.get('model') != model or body.get('stream') is not True:
            raise LocalProviderError('request_identity_mismatch')
        metadata = verify(os.environ.get('AI_LOCAL_PROVIDER', ''), endpoint, model, key)
        expected = os.environ.get('AI_LOCAL_FINGERPRINT', '')
        if expected and (not re.fullmatch('[0-9a-f]{64}', expected) or expected != metadata['fingerprint']):
            raise LocalProviderError('metadata_changed')
        if isinstance(body.get('reasoning'), dict) and body['reasoning'].get('effort') == 'none':
            verify_reasoning_off(os.environ.get('AI_LOCAL_PROVIDER', ''), endpoint, model, metadata, key)
        # The prompt is held in this process until the fresh metadata check.
        request = urllib.request.Request(endpoint, data=json.dumps(body).encode(), headers=headers(key))
        with client().open(request, timeout=75) as response:
            count = 0
            while True:
                line = response.readline(65538)
                if not line: break
                count += len(line)
                if len(line) > 65536 or count > 1024*1024:
                    raise LocalProviderError('response_too_large')
                sys.stdout.buffer.write(line); sys.stdout.buffer.flush()
            print('\n__ALIS_HTTP_STATUS__:'+str(response.status), flush=True)
        return 0
    except urllib.error.HTTPError as error:
        # Preserve status handling without echoing the provider's response body.
        print(json.dumps({'error': {'message': 'Local provider rejected this request.'}}))
        print('__ALIS_HTTP_STATUS__:'+str(error.code), flush=True)
        return 1
    except (LocalProviderError, urllib.error.URLError, OSError, ValueError, TypeError):
        # No provider prose, URL, model text or credentials enter diagnostics.
        print(json.dumps({'error': {'message': 'Local inference could not be verified or completed.'}}))
        print('__ALIS_HTTP_STATUS__:502', flush=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

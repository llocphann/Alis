"""Positive local-weight metadata checks shared by discovery and text I/O.

These checks trust the selected user's server, not a model's text or catalog
name. No inference, download, daemon startup, redirects or proxies are used.
"""
import hashlib
import ipaddress
import json
import math
import urllib.error
import urllib.parse
import urllib.request

MAX_JSON = 1024 * 1024


class LocalProviderError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise LocalProviderError('redirect_blocked')


def origin(endpoint):
    try:
        url = urllib.parse.urlsplit(endpoint)
        port = url.port if url.port is not None else (443 if url.scheme == 'https' else 80)
        if (url.scheme not in ('http', 'https') or url.username is not None or url.password is not None
                or url.query or url.fragment or not ipaddress.ip_address(url.hostname).is_loopback
                or not 1 <= port <= 65535):
            raise ValueError()
    except (ValueError, TypeError):
        raise LocalProviderError('loopback_required') from None
    return urllib.parse.urlunsplit((url.scheme, url.netloc, '', '', ''))


def client():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


def headers(key=''):
    if not isinstance(key, str) or any(c in key for c in '\r\n\x00'):
        raise LocalProviderError('invalid_credential')
    return {'Content-Type': 'application/json', **({'Authorization': 'Bearer '+key} if key else {})}


def request_json(url, key='', timeout=8, payload=None):
    origin(url)
    if not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
        raise LocalProviderError('invalid_timeout')
    request = urllib.request.Request(url, headers=headers(key),
        data=None if payload is None else json.dumps(payload).encode())
    try:
        with client().open(request, timeout=min(timeout, 8)) as response:
            raw = response.read(MAX_JSON+1)
        if len(raw) > MAX_JSON:
            raise LocalProviderError('metadata_too_large')
        return json.loads(raw)
    except (urllib.error.URLError, OSError, ValueError, UnicodeError):
        raise LocalProviderError('metadata_unavailable') from None


def text(value, maximum=160):
    return isinstance(value, str) and 0 < len(value) <= maximum and not any(ord(c) < 32 for c in value)


def remote(row):
    for key in ('remote_model', 'remote_host', 'remote', 'is_remote', 'device_identifier', 'deviceIdentifier'):
        if key not in row: continue
        value = row[key]
        if key in ('remote', 'is_remote'):
            if value is not False: return True
        elif value is not None and (not isinstance(value, str) or value != ''):
            return True
    return False


def lmstudio_metadata(payload, model):
    rows = payload.get('data') if isinstance(payload, dict) else None
    if not isinstance(rows, list) or len(rows) > 2048:
        raise LocalProviderError('invalid_metadata')
    matches = [r for r in rows if isinstance(r, dict) and r.get('id') == model]
    if len(matches) != 1:
        raise LocalProviderError('model_unverified')
    row = matches[0]
    if (remote(row) or row.get('type') not in ('llm', 'vlm')
            or row.get('compatibility_type') not in ('gguf', 'mlx')
            or row.get('state') not in ('loaded', 'not-loaded')
            or not text(row.get('arch')) or not text(row.get('quantization'), 40)
            or type(row.get('max_context_length')) is not int or not 1 <= row['max_context_length'] <= 10**9):
        raise LocalProviderError('model_unverified')
    return {'provider': 'lmstudio', 'model': model, 'format': row['compatibility_type'],
        'architecture': row['arch'], 'quantization': row['quantization'], 'contextTokens': row['max_context_length']}


def ollama_metadata(payload, model):
    if not isinstance(payload, dict) or remote(payload):
        raise LocalProviderError('model_unverified')
    details, info = payload.get('details'), payload.get('model_info')
    if (not isinstance(details, dict) or not isinstance(info, dict) or details.get('format') != 'gguf'
            or not text(details.get('quantization_level'), 40) or not text(info.get('general.architecture'))):
        raise LocalProviderError('model_unverified')
    return {'provider': 'ollama', 'model': model, 'format': 'gguf',
        'architecture': info['general.architecture'], 'quantization': details['quantization_level']}


def fingerprint(metadata):
    return hashlib.sha256(json.dumps(metadata, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def lmstudio_reasoning_off(payload, model, metadata):
    """Match native v1 reasoning options to the positively verified weights.

    General reasoning support does not imply an off switch. Missing/older v1
    metadata leaves Instant unavailable without blocking ordinary local chat.
    """
    rows = payload.get('models') if isinstance(payload, dict) else None
    if not isinstance(rows, list) or len(rows) > 2048:
        return False
    matches = []
    for row in rows:
        if not isinstance(row, dict): continue
        instances = row.get('loaded_instances', [])
        alias = isinstance(instances, list) and any(isinstance(item, dict) and item.get('id') == model for item in instances)
        if row.get('key') == model or alias: matches.append(row)
    if len(matches) != 1:
        return False
    row = matches[0]
    quantization = row.get('quantization')
    capabilities = row.get('capabilities')
    if (remote(row) or row.get('type') != 'llm' or not isinstance(quantization, dict)
            or row.get('format') != metadata.get('format')
            or row.get('architecture') != metadata.get('architecture')
            or quantization.get('name') != metadata.get('quantization')
            or type(row.get('max_context_length')) is not int
            or row['max_context_length'] != metadata.get('contextTokens')
            or not isinstance(capabilities, dict)):
        return False
    reasoning = capabilities.get('reasoning')
    if not isinstance(reasoning, dict):
        return False
    options = reasoning.get('allowed_options')
    return (isinstance(options, list) and 0 < len(options) <= 5
        and all(isinstance(option, str) and option in ('off', 'on', 'low', 'medium', 'high') for option in options)
        and len(set(options)) == len(options) and 'off' in options
        and isinstance(reasoning.get('default'), str) and reasoning['default'] in options)


def verify_reasoning_off(provider, endpoint, model, metadata, key=''):
    if (provider != 'lmstudio' or not lmstudio_reasoning_off(
            request_json(origin(endpoint)+'/api/v1/models', key), model, metadata)):
        raise LocalProviderError('reasoning_off_unverified')


def verify(provider, endpoint, model, key='', timeout=8, payload=None):
    base = origin(endpoint)
    if not text(model):
        raise LocalProviderError('invalid_model')
    if provider == 'lmstudio':
        metadata = lmstudio_metadata(payload if payload is not None else request_json(base+'/api/v0/models', key, timeout), model)
    elif provider == 'ollama':
        metadata = ollama_metadata(payload if payload is not None else request_json(base+'/api/show', key, timeout, {'model': model}), model)
    else:
        raise LocalProviderError('provider_unverified')
    return {**metadata, 'fingerprint': fingerprint(metadata)}

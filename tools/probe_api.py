"""Interactive, read-only API check. Credentials stay in process memory."""
import getpass
import http.cookiejar
import json
import urllib.request
import urllib.parse
import urllib.error
from datetime import datetime, timedelta

cookies = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))
account = input('Account: ')
password = getpass.getpass('Password: ')
url = 'https://passport.seiue.com/login?school_id=3&type=account'
opener.open(url, timeout=30).read()
body = urllib.parse.urlencode({'email': account, 'password': password, 'school_id': '3'}).encode()
response = opener.open(urllib.request.Request(url, body), timeout=30)
response.read()
print('Login destination:', response.url)
body = urllib.parse.urlencode({'response_type': 'token', 'client_id': 'GpxvnjhVKt56qTmnPWH1sA'}).encode()
token = json.load(opener.open(urllib.request.Request('https://passport.seiue.com/authorize', body), timeout=30))
print('Token response keys:', list(token))
if 'access_token' not in token:
    raise SystemExit('Authentication did not return an access token')
headers = {'Authorization': token.get('token_type', 'Bearer') + ' ' + token['access_token']}

def call(path, query=None, service='chalk'):
    if service not in {'chalk', 'scms', 'sgms', 'sams', 'vnas'}:
        raise ValueError('Unsupported service')
    target = 'https://api.seiue.com/' + service + path
    if query:
        target += '?' + urllib.parse.urlencode(query)
    return json.load(opener.open(urllib.request.Request(target, headers=headers), timeout=30))

info = call('/oauth/info', {'expand': 'reflections'})
print('Info keys:', list(info))
print('Available identities:', [{k: r.get(k) for k in ['id', 'role', 'school_id', 'is_default', 'status', 'disabled']} for r in info['reflections']])
reflection = next((r for r in info['reflections'] if str(r['id']) == str(token.get('active_reflection_id'))), next(r for r in info['reflections'] if str(r['school_id']) == '3' and r.get('is_default')))
print('Reflection keys:', list(reflection))
headers.update({'X-Reflection-Id': str(reflection['id']), 'X-School-Id': '3', 'X-Role': reflection['role']})
now = datetime.now()
start = (now - timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
for label, path, query in [
    ('calendar', '/calendar/personals/' + str(reflection['id']) + '/events', {'start_time': start.strftime('%Y-%m-%d %H:%M:%S'), 'end_time': (start+timedelta(days=7)).strftime('%Y-%m-%d %H:%M:%S'), 'expand': 'address,initiators'}),
    ('notices', '/me/received-messages', {'type': 'message', 'owner.id': reflection['id'], 'sort': '-published_at,-created_at', 'per_page': 2, 'expand': 'sender_reflection'}),
    ('system', '/me/received-messages', {'notice': 'true', 'owner.id': reflection['id'], 'per_page': 2, 'expand': 'aggregated_messages'}),
]:
    try:
        data = call(path, query)
        print(label, 'count:', len(data), 'sample:', json.dumps(data[:1] if label == 'calendar' else [{k: r.get(k) for k in ['_id', 'title', 'published_at', 'type']} for r in data], ensure_ascii=False)[:4500])
    except urllib.error.HTTPError as error:
        print(label, error.code, error.read().decode()[:700])
print('Read-only query ready. Enter a JSON object with path and query, or exit.')
while True:
    raw = input('query> ')
    if raw == 'exit':
        break
    try:
        request = json.loads(raw)
        data = call(request['path'], request.get('query'), request.get('service', 'chalk'))
        fields = request.get('fields')
        if fields and isinstance(data, list):
            data = [{k: row.get(k) for k in fields} for row in data]
        if request.get('schema'):
            def schema(value, depth=0):
                if depth > 4:
                    return type(value).__name__
                if isinstance(value, dict):
                    return {k: schema(v, depth + 1) for k, v in value.items()}
                if isinstance(value, list):
                    return {'count': len(value), 'sample': schema(value[0], depth + 1) if value else None}
                return type(value).__name__
            data = schema(data)
        print(json.dumps(data, ensure_ascii=False)[:12000])
    except Exception as error:
        print(type(error).__name__, str(error))

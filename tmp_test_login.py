import json
import urllib.request

url = 'https://legal-carrots-fall.loca.lt/api/accounts/login/'
data = json.dumps({'email': 'test@example.com', 'password': 'wrongpass'}).encode()
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'}, method='POST')

try:
    with urllib.request.urlopen(req, timeout=20) as r:
        print('status', r.status)
        print(r.read().decode())
except Exception as e:
    print(type(e).__name__, e)

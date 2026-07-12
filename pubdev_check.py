import urllib.request, json
for p in ['firebase_core', 'firebase_messaging', 'flutter_local_notifications']:
    data = json.loads(urllib.request.urlopen(f'https://pub.dev/api/packages/{p}').read())
    latest = data['latest']
    sdk = latest['pubspec']['environment'].get('sdk', 'unknown')
    print(p, latest['version'], sdk)

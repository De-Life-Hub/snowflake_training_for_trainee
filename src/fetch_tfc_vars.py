import sys, json

data = json.load(sys.stdin)
for var in data['data']:
    key = var['attributes']['key']
    value = var['attributes']['value'] or ''
    sensitive = var['attributes']['sensitive']
    if not sensitive:
        print(f'{key}={value}')
        if key == 'DBT_ENV_SECRET_DATABASE':
            print(f'DBT_DATABASE={value}')
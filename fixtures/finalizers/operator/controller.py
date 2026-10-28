"""Small real finalizer controller. A ConfigMap models an external allocation.

It never creates Azure resources; the finalizer and Kubernetes deletion behavior
are real. Tokens are reread to support projected service-account token rotation.
"""
import json
import os
import re
import ssl
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

FINALIZER = 'cleanup.reliability.flatspell.io/allocation'


def reconcile(item, api, namespace):
    name = item['metadata']['name']
    uid = item['metadata']['uid']
    allocation = item['spec']['allocationName']
    if not re.fullmatch(r'allocation-[a-z0-9-]+', allocation):
        raise ValueError('Unexpected allocation name')
    custom = f'/apis/cleanup.reliability.flatspell.io/v1/namespaces/{namespace}/cleanuptasks/{name}'
    marker = f'/api/v1/namespaces/{namespace}/configmaps/{allocation}'
    finalizers = item['metadata'].get('finalizers', [])
    if item['metadata'].get('deletionTimestamp'):
        existing = api('GET', marker)
        if existing and existing['metadata'].get('labels', {}).get('allocation-owner') != uid:
            raise ValueError('Allocation belongs to another object; refusing deletion')
        if existing:
            api('DELETE', marker, {'apiVersion': 'v1', 'kind': 'DeleteOptions',
                                   'preconditions': {'uid': existing['metadata']['uid']}})
        if FINALIZER in finalizers:
            api('PATCH', custom, {'metadata': {'resourceVersion': item['metadata']['resourceVersion'],
                                             'finalizers': [f for f in finalizers if f != FINALIZER]}})
        return
    if FINALIZER not in finalizers:
        api('PATCH', custom, {'metadata': {'resourceVersion': item['metadata']['resourceVersion'],
                                         'finalizers': finalizers + [FINALIZER]}})
    existing = api('GET', marker)
    if existing and existing['metadata'].get('labels', {}).get('allocation-owner') != uid:
        raise ValueError('Existing allocation belongs to another object')
    if not existing:
        api('POST', f'/api/v1/namespaces/{namespace}/configmaps', {
            'apiVersion': 'v1', 'kind': 'ConfigMap',
            'metadata': {'name': allocation, 'labels': {'allocation-owner': uid}},
            'data': {'note': 'Fixture for external cleanup; no Azure allocation is created.'},
        })


def main():
    namespace = os.environ['POD_NAMESPACE']
    token_dir = Path('/var/run/secrets/kubernetes.io/serviceaccount')
    context = ssl.create_default_context(cafile=str(token_dir / 'ca.crt'))
    host = os.environ['KUBERNETES_SERVICE_HOST']
    port = os.environ.get('KUBERNETES_SERVICE_PORT_HTTPS', '443')

    def api(method, path, body=None):
        request = Request(f'https://{host}:{port}{path}', method=method,
                          data=json.dumps(body).encode() if body is not None else None,
                          headers={'Authorization': 'Bearer ' + (token_dir / 'token').read_text().strip(),
                                   'Content-Type': 'application/merge-patch+json' if method == 'PATCH' else 'application/json'})
        try:
            with urlopen(request, context=context, timeout=15) as response:
                return json.load(response)
        except HTTPError as error:
            if error.code == 404:
                return None
            raise

    while True:
        try:
            items = api('GET', f'/apis/cleanup.reliability.flatspell.io/v1/namespaces/{namespace}/cleanuptasks')
            for item in items['items']:
                reconcile(item, api, namespace)
        except Exception as error:
            print(f'reconcile failed: {type(error).__name__}', flush=True)
        time.sleep(2)


if __name__ == '__main__':
    main()

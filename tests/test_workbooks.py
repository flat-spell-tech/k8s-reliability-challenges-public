import importlib.util
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
import sys
import yaml

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('operator_fixture', ROOT / 'fixtures/finalizers/operator/controller.py')
operator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(operator)


class FinalizerContract(unittest.TestCase):
    def test_controller_imports_from_its_mounted_directory(self):
        # In the pod this directory is sys.path[0]. Naming the script operator.py
        # would shadow Python's standard-library operator module during startup.
        result = subprocess.run([sys.executable, '-c', 'import controller; print(controller.FINALIZER)'],
                                cwd=ROOT / 'fixtures/finalizers/operator', capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), operator.FINALIZER)

    def item(self, deleting=False):
        return {
            'metadata': {'name': 'example', 'uid': 'task-uid', 'resourceVersion': '7',
                         'finalizers': [operator.FINALIZER, 'other.example/retain'],
                         **({'deletionTimestamp': '2026-10-27T12:00:00Z'} if deleting else {})},
            'spec': {'allocationName': 'allocation-example'},
        }

    def test_cleanup_deletes_owned_allocation_before_removing_only_its_finalizer(self):
        calls = []
        marker = {'metadata': {'uid': 'marker-uid', 'labels': {'allocation-owner': 'task-uid'}}}

        def api(method, path, body=None):
            calls.append((method, path, body))
            return marker if method == 'GET' else {}

        operator.reconcile(self.item(True), api, 'workbook-09')
        self.assertEqual([c[0] for c in calls], ['GET', 'DELETE', 'PATCH'])
        self.assertEqual(calls[1][2]['preconditions'], {'uid': 'marker-uid'})
        self.assertEqual(calls[2][2]['metadata'], {'resourceVersion': '7', 'finalizers': ['other.example/retain']})

    def test_cleanup_refuses_an_allocation_owned_by_another_object(self):
        calls = []

        def api(method, path, body=None):
            calls.append(method)
            return {'metadata': {'labels': {'allocation-owner': 'another-uid'}}}

        with self.assertRaisesRegex(ValueError, 'another object'):
            operator.reconcile(self.item(True), api, 'workbook-09')
        self.assertEqual(calls, ['GET'])

    def test_finalizer_remains_when_external_cleanup_fails(self):
        calls = []

        def api(method, path, body=None):
            calls.append(method)
            if method == 'DELETE':
                raise OSError('simulated API failure')
            return {'metadata': {'uid': 'marker', 'labels': {'allocation-owner': 'task-uid'}}}

        with self.assertRaises(OSError):
            operator.reconcile(self.item(True), api, 'workbook-09')
        self.assertEqual(calls, ['GET', 'DELETE'])

    def test_missing_allocation_still_allows_finalizer_completion(self):
        calls = []

        def api(method, path, body=None):
            calls.append(method)
            return None

        operator.reconcile(self.item(True), api, 'workbook-09')
        self.assertEqual(calls, ['GET', 'PATCH'])

    def test_live_reconcile_adds_finalizer_before_allocating(self):
        item = self.item()
        item['metadata']['finalizers'] = []
        calls = []

        def api(method, path, body=None):
            calls.append((method, body))
            return None

        operator.reconcile(item, api, 'workbook-09')
        self.assertEqual([c[0] for c in calls], ['PATCH', 'GET', 'POST'])
        self.assertEqual(calls[-1][1]['metadata']['labels']['allocation-owner'], 'task-uid')


class OrchestrationContract(unittest.TestCase):
    def executable(self, path, text):
        path.write_text(text)
        path.chmod(0o755)

    def test_run_command_transport_success_is_not_remote_action_success(self):
        config = {'resource_group': 'test-rg', 'runner_name': 'test-runner'}
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            self.executable(directory / 'terraform', '#!/usr/bin/env python3\nprint(' + repr(json.dumps(config)) + ')\n')
            self.executable(directory / 'az', '''#!/usr/bin/env python3
import os,json
message='[stderr] remote apply failed'
if os.environ.get('TEST_ACTION_OK') == '1':
    message='[stdout]\\nLAB_ACTION_OK:01-private-api-dns:setup\\n[stderr]'
print(json.dumps({'value':[{'code':'ProvisioningState/succeeded','message':message}]}))
''')
            env = {**os.environ, 'PATH': folder + os.pathsep + os.environ['PATH']}
            isolated = directory / 'repo'
            (isolated / 'scripts').mkdir(parents=True)
            (isolated / 'workbooks/01-private-api-dns/infra').mkdir(parents=True)
            shutil.copyfile(ROOT / 'scripts/run-on-runner.sh', isolated / 'scripts/run-on-runner.sh')
            command = ['bash', str(isolated / 'scripts/run-on-runner.sh'), '01-private-api-dns', 'setup']
            failed = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('No success sentinel', failed.stderr)
            success = subprocess.run(command, env={**env, 'TEST_ACTION_OK': '1'}, capture_output=True, text=True)
            self.assertEqual(success.returncode, 0, success.stderr)

    def test_readiness_wait_rejects_a_stale_ready_condition(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            counter = directory / 'count'
            self.executable(directory / 'kubectl', '''#!/usr/bin/env python3
import json,os
from pathlib import Path
p=Path(os.environ['TEST_COUNTER']);n=int(p.read_text())+1 if p.exists() else 1;p.write_text(str(n))
print(json.dumps({'metadata':{'generation':2},'status':{'observedGeneration':1 if n==1 else 2,'conditions':[{'type':'Ready','status':'True'}]}}))
''')
            self.executable(directory / 'sleep', '#!/usr/bin/env bash\nexit 0\n')
            env = {**os.environ, 'PATH': folder + os.pathsep + os.environ['PATH'], 'TEST_COUNTER': str(counter)}
            result = subprocess.run(['bash', str(ROOT / 'scripts/wait-ready.sh'), 'helmrelease/example', 'test'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(counter.read_text(), '2')

    def test_wrong_cluster_context_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            self.executable(directory / 'kubectl', '#!/usr/bin/env bash\necho https://production.example\n')
            env = {**os.environ, 'PATH': folder + os.pathsep + os.environ['PATH'], 'LAB_PRIVATE_FQDN': 'lab.example', 'KUBECONFIG': '/tmp/not-a-real-config'}
            result = subprocess.run(['bash', str(ROOT / 'scripts/assert-context.sh')], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Refusing', result.stderr)


class WorkbookContract(unittest.TestCase):
    def test_schema_rollback_fixture_is_incompatible_until_repaired(self):
        enums = {}
        defaults = {}
        for chart in ['schema-v1', 'schema-v2', 'schema-compatible']:
            base = ROOT / 'fixtures/charts' / chart
            schema = yaml.safe_load((base / 'crds/schema.yaml').read_text())
            enums[chart] = schema['spec']['versions'][0]['schema']['openAPIV3Schema']['properties']['spec']['properties']['mode']['enum']
            defaults[chart] = yaml.safe_load((base / 'values.yaml').read_text())['mode']
        self.assertIn(defaults['schema-v1'], enums['schema-v1'])
        self.assertNotIn(defaults['schema-v1'], enums['schema-v2'])
        self.assertIn(defaults['schema-v2'], enums['schema-compatible'])
        self.assertIn(defaults['schema-v1'], enums['schema-compatible'])

    def test_each_workbook_has_independent_stages_and_usable_local_doc_links(self):
        import re
        workbooks = sorted((ROOT / 'workbooks').iterdir())
        self.assertEqual(len(workbooks), 10)
        for workbook in workbooks:
            self.assertTrue((workbook / 'README.md').is_file())
            for stage in ['infra', 'bootstrap', 'scenario']:
                self.assertTrue(list((workbook / stage).glob('*.tf')))
        for document in list(ROOT.rglob('README.md')) + list((ROOT / 'docs').glob('*.md')):
            if '.terraform' in document.parts:
                continue
            for link in re.findall(r'\]\(([^)]+)\)', document.read_text()):
                if '://' not in link and not link.startswith('#'):
                    self.assertTrue((document.parent / link.split('#')[0]).exists(), f'{document}: {link}')


if __name__ == '__main__':
    unittest.main()

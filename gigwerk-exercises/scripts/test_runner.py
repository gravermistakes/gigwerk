import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

MODULE = Path(__file__).with_name('verify_catalogue.py')
BACKEND = Path(__file__).resolve().parents[1] / 'backend' / 'synquid-ocaml'

class RunnerTests(unittest.TestCase):
    def verify(self, output='f = \\xs . xs\n', signature="'a list -> 'a list", strength='full', with_tests=True):
        self.assertTrue(MODULE.exists(), 'missing catalogue verification runner')
        spec = importlib.util.spec_from_file_location('catalogue_runner', MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory/'synthesis.out').write_text(output)
            (directory/'contract.sq').write_text('data List a where\n  Nil :: List a\n  Cons :: x:a -> xs:List a -> List a\n')
            (directory/'interface.json').write_text(json.dumps({'entrypoints':[{'name':'f','signature':signature}], 'types':[]}))
            (directory/'assessment.json').write_text(json.dumps({'contract_status':'ready','specification_strength':strength,'synthesis_status':'candidate'}))
            if with_tests:
                (directory/'test_generated.ml').write_text('let () = assert (Generated.f [1;2] = [1;2]); print_endline "PASS fixture"\n')
            return module.verify_item(directory, backend=BACKEND)

    def test_compiler_and_semantic_success(self):
        self.assertEqual(self.verify()['status'], 'fulfilled')

    def test_semantic_failure_is_not_solved(self):
        self.assertEqual(self.verify(output='f = \\xs . Nil\n')['status'], 'tests_failed')

    def test_wrong_signature_is_compile_failure(self):
        self.assertEqual(self.verify(signature='bool -> int list')['status'], 'compile_failed')

    def test_missing_tests_not_fulfilled(self):
        self.assertNotEqual(self.verify(with_tests=False)['status'], 'fulfilled')

    def test_partial_contract_never_fulfilled(self):
        self.assertEqual(self.verify(strength='partial')['status'], 'tests_passed_partial_contract')

    def test_hole_not_lowered(self):
        self.assertEqual(self.verify(output='f = \\xs . ??\n')['status'], 'lowering_failed')

    def test_missing_catalogue_items_are_reported(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'items').mkdir()
            (root/'catalogue.json').write_text(json.dumps({'items':[{'id':'missing_a'},{'id':'missing_b'}]}))
            run = subprocess.run([sys.executable, str(MODULE), '--root', str(root)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            results = json.loads((root/'results.json').read_text())
            self.assertEqual(len(results), 2, 'declared missing items must not disappear')
            self.assertTrue(all(row['status']=='missing' for row in results))

if __name__ == '__main__':
    unittest.main()

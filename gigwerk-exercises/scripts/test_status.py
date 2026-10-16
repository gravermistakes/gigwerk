import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).with_name('status.py')

class StatusTests(unittest.TestCase):
    def classify(self, **kwargs):
        self.assertTrue(MODULE.exists(), 'missing fulfillment status gate')
        spec = importlib.util.spec_from_file_location('exercise_status', MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        values = dict(contract='ready', strength='full', synthesis='candidate', lowering=True,
                      interface=True, compiled=True, tests=True, test_exit=0)
        values.update(kwargs)
        return module.classify(**values)

    def test_full_verified_candidate(self):
        self.assertEqual(self.classify(), 'fulfilled')

    def test_partial_never_fulfilled(self):
        self.assertEqual(self.classify(strength='partial'), 'tests_passed_partial_contract')

    def test_candidate_not_implementation(self):
        self.assertEqual(self.classify(compiled=False), 'compile_failed')

    def test_interface_required(self):
        self.assertEqual(self.classify(interface=False), 'interface_unverified')

    def test_tests_required(self):
        self.assertEqual(self.classify(tests=False), 'tests_failed')

    def test_failed_exit_overrides_claimed_tests(self):
        self.assertEqual(self.classify(test_exit=1), 'tests_failed')

    def test_lowering_failure(self):
        self.assertEqual(self.classify(lowering=False), 'lowering_failed')

    def test_timeout_never_fulfilled(self):
        self.assertEqual(self.classify(synthesis='timeout'), 'synthesis_timeout')

    def test_requirements_feature_gap(self):
        self.assertEqual(self.classify(contract='requires_features', synthesis='not_attempted'), 'requires_features')

    def test_no_tests_for_partial(self):
        self.assertEqual(self.classify(strength='partial', tests=False), 'tests_failed')

if __name__ == '__main__':
    unittest.main()

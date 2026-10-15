import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).with_name('lower.py')


class LowererTests(unittest.TestCase):
    def lower(self, source):
        self.assertTrue(MODULE.exists(), 'missing checked syntax adapter')
        spec = importlib.util.spec_from_file_location('synquid_lower', MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.lower(source, 'insert')

    def test_keeps_body_instead_of_substituting_algorithm(self):
        result = self.lower('insert = \\x . \\t . t\n')
        self.assertIn('let rec insert', result)
        self.assertTrue(result.rstrip().endswith('t'))

    def test_constructor_application_becomes_tuple(self):
        result = self.lower('insert = \\x . \\t . Node x t Empty\n')
        self.assertIn('Node (x, t, Empty)', result)

    def test_layout_match_and_pattern_arguments(self):
        result = self.lower('insert = \\x . \\t .\n  match t with\n    Empty -> Empty\n    Node key left right -> Node key left right\n(Goals: 1)\n')
        self.assertIn('| Empty ->', result)
        self.assertIn('| Node (key, left, right) ->', result)

    def test_preserves_comparison_and_nested_conditionals(self):
        result = self.lower('insert = \\x . \\t . if x <= x then if x <= x then t else Empty else t\n')
        self.assertEqual(result.count('if '), 2)
        self.assertEqual(result.count('else'), 2)
        self.assertIn('<=', result)

    def test_rejects_unknown_symbol(self):
        with self.assertRaises(ValueError):
            self.lower('insert = \\x . \\t . system x\n')

    def test_rejects_holes(self):
        with self.assertRaises(ValueError):
            self.lower('insert = \\x . \\t . ??\n')

    def test_rejects_wrong_constructor_arity(self):
        with self.assertRaises(ValueError):
            self.lower('insert = \\x . \\t . Node x t\n')

    def test_rejects_wrong_pattern_arity(self):
        with self.assertRaises(ValueError):
            self.lower('insert = \\x . \\t . match t with\n  Node key -> t\n')

    def test_rejects_partial_match(self):
        with self.assertRaises(ValueError):
            self.lower('insert = \\x . \\t . match t with\n  Empty -> t\n')

    def test_rejects_unbound_variable(self):
        with self.assertRaises(ValueError):
            self.lower('insert = \\x . \\t . missing\n')

    def test_rejects_duplicate_goal(self):
        with self.assertRaises(ValueError):
            self.lower('insert = \\x . \\t . t\ninsert = \\x . \\t . Empty\n')


if __name__ == '__main__':
    unittest.main()

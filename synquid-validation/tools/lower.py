#!/usr/bin/env python3
"""Narrow Synquid-stdout -> OCaml adapter for this BST experiment.

Not a general Synquid compiler. No algorithm templates or model calls.
Supported: two top-level lambdas, variables, Empty/Node, full single-level
BST matches, pure applications, comparisons, Boolean connectives and if.
Unsupported terms are rejected. The exported key domain is OCaml int.
"""
import argparse
from pathlib import Path
import re

ARITY = {'Empty': 0, 'Node': 3}
PREC = {'||': 1, '&&': 2, '==': 3, '!=': 3, '<=': 3, '>=': 3, '<': 3, '>': 3}
KEYWORDS = {'if', 'then', 'else', 'match', 'with', 'let', 'in', 'fun', 'rec', 'type', 'module', 'open', 'and', 'true', 'false'}
TOKEN = re.compile(r'\s+|->|<=|>=|==|!=|&&|\|\||[A-Za-z_][A-Za-z_0-9\']*|[()\\.<>|]')


def identifier(value):
    if not re.fullmatch(r'[a-z][A-Za-z_0-9\']*', value) or value in KEYWORDS:
        raise ValueError('unsupported binder: ' + value)
    return value


class Parser:
    def __init__(self, text):
        # Turn the observed layout-delimited BST branches into explicit bars.
        lines = []
        for line in text.splitlines():
            if re.match(r'\s*(Empty|Node)\b[^\n]*->', line):
                line = '| ' + line.strip()
            lines.append(line)
        text = '\n'.join(lines)
        self.tokens = []
        offset = 0
        for token in TOKEN.finditer(text):
            if token.start() != offset:
                raise ValueError('unsupported token near ' + text[offset:offset + 20])
            offset = token.end()
            if not token.group().isspace():
                self.tokens.append(token.group())
        if offset != len(text):
            raise ValueError('unsupported trailing input')
        self.pos = 0
        self.match_depth = 0

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def take(self, expected=None):
        value = self.peek()
        if value is None or (expected is not None and value != expected):
            raise ValueError(f'expected {expected}, got {value}')
        self.pos += 1
        return value

    def expr(self, minimum=0):
        value = self.term()
        while self.peek() in PREC and PREC[self.peek()] >= minimum:
            op = self.take()
            value = ('op', op, value, self.expr(PREC[op] + 1))
        return value

    def term(self):
        if self.peek() == 'if':
            self.take('if')
            cond = self.expr()
            self.take('then')
            yes = self.expr()
            self.take('else')
            no = self.expr()
            return ('if', cond, yes, no)
        if self.peek() == 'match':
            if self.match_depth:
                raise ValueError('nested layout matches are outside this adapter')
            self.match_depth += 1
            self.take('match')
            subject = self.expr()
            self.take('with')
            cases = []
            while self.peek() == '|':
                self.take('|')
                constructor = self.take()
                if constructor not in ARITY:
                    raise ValueError('unknown pattern constructor')
                names = []
                while self.peek() != '->':
                    names.append(identifier(self.take()))
                self.take('->')
                if len(names) != ARITY[constructor] or len(set(names)) != len(names):
                    raise ValueError('invalid pattern arity/binders')
                cases.append((constructor, names, self.expr()))
            self.match_depth -= 1
            if len(cases) != 2 or {c[0] for c in cases} != set(ARITY):
                raise ValueError('partial or duplicate BST match')
            return ('match', subject, cases)
        value = self.atom()
        while self.peek() == '(' or (self.peek() is not None
              and re.fullmatch(r'[A-Za-z_][A-Za-z_0-9\']*', self.peek())
              and self.peek() not in KEYWORDS):
            value = ('app', value, self.atom())
        return value

    def atom(self):
        if self.peek() == '(':
            self.take('(')
            result = self.expr()
            self.take(')')
            return result
        value = self.take()
        if value in KEYWORDS or not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9\']*', value):
            raise ValueError('unsupported atom: ' + value)
        return ('symbol', value)


def emit(tree, scope, function, level=0):
    kind = tree[0]
    if kind == 'symbol':
        name = tree[1]
        if name not in scope and name not in ARITY and name != function:
            raise ValueError('unbound or unknown symbol: ' + name)
        if name == 'Node':
            raise ValueError('partially applied Node')
        return name
    if kind == 'app':
        args = []
        head = tree
        while head[0] == 'app':
            args.insert(0, head[2])
            head = head[1]
        if head[0] == 'symbol' and head[1] in ARITY:
            name = head[1]
            if len(args) != ARITY[name]:
                raise ValueError('invalid constructor arity')
            return name + ' (' + ', '.join(emit(a, scope, function) for a in args) + ')'
        if head != ('symbol', function) or len(args) != 2:
            raise ValueError('unsupported callable or arity')
        return '(' + function + ' ' + ' '.join('(' + emit(a, scope, function) + ')' for a in args) + ')'
    if kind == 'op':
        op = {'==': '=', '!=': '<>'}.get(tree[1], tree[1])
        return '(' + emit(tree[2], scope, function) + ' ' + op + ' ' + emit(tree[3], scope, function) + ')'
    if kind == 'if':
        prefix = '  ' * level
        return ('if ' + emit(tree[1], scope, function) + ' then\n'
                + prefix + '  ' + emit(tree[2], scope, function, level + 1) + '\n'
                + prefix + 'else\n' + prefix + '  ' + emit(tree[3], scope, function, level + 1))
    if kind == 'match':
        prefix = '  ' * level
        parts = ['match ' + emit(tree[1], scope, function) + ' with']
        for constructor, names, body in tree[2]:
            pattern = constructor + (' (' + ', '.join(names) + ')' if names else '')
            parts.append(prefix + '| ' + pattern + ' ->\n' + prefix + '  '
                         + emit(body, scope | set(names), function, level + 1))
        return '\n'.join(parts)
    raise ValueError('unknown AST node')


def lower(source, function='insert'):
    identifier(function)
    starts = list(re.finditer(r'^' + re.escape(function) + r'\s*=\s*', source, re.M))
    if len(starts) != 1:
        raise ValueError('expected exactly one goal definition')
    body = source[starts[0].end():]
    body = re.split(r'^\((?:Goals|Measures|Spec size|Solution size):', body, maxsplit=1, flags=re.M)[0]
    parser = Parser(body)
    names = []
    while parser.peek() == '\\':
        parser.take('\\')
        names.append(identifier(parser.take()))
        parser.take('.')
    if len(names) != 2 or len(set(names)) != 2:
        raise ValueError('expected two distinct lambda arguments')
    tree = parser.expr()
    if parser.peek() is not None:
        raise ValueError('unconsumed program input')
    code = emit(tree, set(names), function, 1)
    return ("(* Mechanically lowered Synquid output; no algorithm substitution. *)\n"
            "type 'a bst = Empty | Node of 'a * 'a bst * 'a bst\n\n"
            f"let rec {function} ({names[0]} : int) ({names[1]} : int bst) : int bst =\n  "
            + code + '\n')


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('source', type=Path)
    cli.add_argument('destination', type=Path)
    args = cli.parse_args()
    args.destination.write_text(lower(args.source.read_text()))

"""Conservative benchmark status transitions; solver candidates are not success."""


def classify(*, contract, strength, synthesis, lowering, interface, compiled, tests, test_exit):
    if synthesis != 'candidate':
        if synthesis == 'timeout':
            return 'synthesis_timeout'
        if contract in {'requires_features', 'ambiguous', 'not_expressible'}:
            return contract
        return 'synthesis_' + synthesis
    if not lowering:
        return 'lowering_failed'
    if not interface:
        return 'interface_unverified'
    if not compiled:
        return 'compile_failed'
    if not tests or test_exit != 0:
        return 'tests_failed'
    if strength != 'full':
        return 'tests_passed_partial_contract'
    if contract != 'ready':
        return 'tests_passed_contract_unresolved'
    return 'fulfilled'

# GAS_Engine — UE 5.7.4 Contract Matrix

Baseline GAS_Engine: 0db4c24441184a67c1b9b606af6ce9d8ec6b917c
Reference: Unreal Engine 5.7.4, CL 51494982

Allowed states:
- COMPLETE
- PARTIAL
- ABSENT
- EXPLICIT_DEVIATION

Rules:
1. COMPLETE requires a named automated scenario and evidence.
2. PARTIAL is mandatory when any documented case is still absent.
3. EXPLICIT_DEVIATION is not failure, but cannot be counted as Unreal parity.
4. A class name or unit-test count is never evidence by itself.
5. TURN_BASED and external bridges are GAS_Engine extensions.

| Area | State at phase start | Closure package |
|---|---|---|
| Runtime correctness | PARTIAL | F5.1 |
| Attribute aggregation | PARTIAL | F5.2 |
| Ability lifecycle/commit | PARTIAL | F5.2 |
| Specs/captures/stacking | PARTIAL | F5.2 |
| Tags/events | PARTIAL | F5.2 |
| Authoring/Composer | PARTIAL | F5.3 |
| Targeting/tasks/animation/cues | PARTIAL | F5.4 |
| Authority/replication/prediction | ABSENT | F5.5 |
| Performance/determinism certification | ABSENT | F5.6 |

## Closed packages

The table above is the state at phase start and stays that way. What a package
closed is its own receipt, whose every named scenario is checked against the
suite by `tooling/parity_receipt.py`.

| Package | Receipt |
|---|---|
| F5.2 | `artifacts/parity/GATE_F5_2.md` |
| F5.3 | `artifacts/parity/GATE_F5_3.md` |

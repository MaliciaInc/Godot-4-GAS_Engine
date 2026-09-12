# Producing the reference corpus

The goldens under `test/parity/goldens/` are the only thing in this repository
allowed to be called parity. A golden earns that word by carrying outputs a real
Unreal Engine 5.7.4 produced; until it does, it says `NOT_UE_VERIFIED` and
`tooling/parity_diff.py` stops.

That is not pedantry. This repository already contains a corpus authored from
Unreal's documented behaviour — `test/parity/contracts/` — and it says so at the
top of every file: *no Unreal process is run*. Those are reviewable claims and
they are useful, but a claim is not a measurement, and the difference matters
exactly where somebody would most like to blur it: the cases where our reading
of the documentation could be wrong.

## What has to be produced

Ten scenarios, one file each, already written out with everything except what
only Unreal can answer. Each carries its inputs, the tolerance a comparison
should use, and whether execution order is observable in it.

| scenario | what it decides |
|---|---|
| `legacy_multiply_one_and_a_half_twice` | whether the legacy name is the additive arm |
| `multiply_compound_one_and_a_half_twice` | and what the compounding one does with the same numbers |
| `legacy_divide` | the other half of the legacy pair |
| `double_override_same_channel` | **D-11**: which of two overrides in one channel wins |
| `override_across_channels` | whether a later channel's override is the answer |
| `short_inhibition_with_execute_and_reset_period` | how a sub-period inhibition ticks |
| `stack_count_factor_off_and_on` | what the reference does by default with stack count |
| `modifier_source_and_target_tag_qualification` | which side a qualification is read from |
| `bonus_magnitude` | how a captured magnitude composes its coefficients |
| `magnitude_up_to_channel` | what "as it stood up to a channel" reads |

## The harness, and what it produced

`harness/` is the project that produced them. It was built and run against the
installed engine on 2026-09-11: **Unreal Engine 5.7.4 CL 51494982**, at
`C:\Program Files\Epic Games\UE_5.7`. An earlier receipt said that engine was
not installed; nobody had looked, and it was there.

Run it with:

```text
Build.bat UEParityEditor Win64 Development -Project=<harness>/UEParity.uproject
UnrealEditor-Cmd.exe <harness>/UEParity.uproject -run=pythonscript \
    -script=<harness>/run_scenarios.py -unattended -nopause -nosplash -NullRHI
```

It needs the **.NET Framework 4.8 SDK** (`Microsoft.Net.Component.4.8.SDK`, or
Microsoft's standalone Developer Pack). Without it the editor target does not
build at all: `SwarmInterface.Build.cs` throws *"Could not find NetFxSDK install
dir"*. The game target builds without it and cannot run, because a monolithic
binary needs cooked content and cooking needs the editor.

The C++ module is small on purpose. Everything a scenario is made of is
reachable from Python except three things, and those are why it exists:
`UAbilitySystemComponent::InitAbilityActorInfo` and `RegisterComponent` are not
`UFUNCTION`s and every apply path dereferences the actor info; and a carrier has
to implement `IAbilitySystemInterface`, because the source tags a modifier
qualifies on are captured through `GetAbilitySystemComponentFromActor`, which
finds a component no other way.

### Eight of ten

| scenario | what the reference answered |
|---|---|
| `legacy_multiply_one_and_a_half_twice` | 20.0 - the legacy name is the additive arm |
| `multiply_compound_one_and_a_half_twice` | 22.5 |
| `legacy_divide` | 5.0 |
| `double_override_same_channel` | **40.0** - the first override registered stands |
| `override_across_channels` | 70.0 - the later channel stands |
| `stack_count_factor_off_and_on` | 15.0 with the factor off, 25.0 with it on |
| `bonus_magnitude` | 105.0 |
| `magnitude_up_to_channel` | health 85.0, attack 115.0 |

The two override rows were each run a second time with the pair swapped, which
is what makes "the first one stands" a measurement rather than a reading of the
result: swapped, they answer 70.0 and 40.0.

This engine agrees with all eight.

### Two that are not measured, and why

Neither is written into its golden. A harness that answers the same thing for
every variant is also what a harness that applied nothing answers, and the
difference is the whole point of this corpus.

**`modifier_source_and_target_tag_qualification`** - all four variants answer
10.0, and the controls say that is the harness. A modifier with no requirement
across the same source-to-target path applies (10.0 -> 15.0). A modifier whose
target requirement *is* met answers 10.0 - with the tag added before the effect
and again with it added after, with the target's owned tags read back as
`Status.Burning` both times, and with the requirement expressed both as
`RequireTags` and as a `TagQuery`.

**`short_inhibition_with_execute_and_reset_period`** - the control with nothing
inhibited executes zero times over a world that reaches 5.1 seconds, when it
should execute most often of all. The period is not the problem and that was
measured too: the definition says 1.0, the spec built from it says 1.0, the
duration says infinite, and `bExecutePeriodicEffectOnApplication` is on, which
should have executed once at application with no clock involved at all. So the
periodic machinery needs something this harness's world does not give it, and
the next person has that to look at rather than a shrug.

## How

1. Open Unreal Engine 5.7.4 (changelist 51494982) with a project that has the
   Gameplay Abilities plugin enabled. The version and changelist are stamped in
   every golden; producing them on a different build means changing those fields
   too, and the corpus is then about that build.
2. Build each scenario from the `inputs` block of its golden: the attribute base
   values, the modifiers with their operations, channels and magnitudes, the
   tags, and any variants listed. The blocks are deliberately literal so that
   two people building the same scenario build the same thing.
3. Run it and record what happened. Fill in `outputs` with the values the
   reference produced, and — where `execution_order_observable` is true — fill
   in `execution_order` with the order they were observed in.
4. Change `evidence` from `NOT_UE_VERIFIED` to `UE_VERIFIED` on that golden, and
   on no other.
5. Run `python tooling/parity_diff.py`. It compares each verified golden with
   what this engine produced in
   `artifacts/parity/results/ue_scenarios.json`, to that golden's tolerance.

## What not to do

- Do not fill in `outputs` from the documentation, from this engine's own
  behaviour, or from a reading of Unreal's source. `parity_diff.py` cannot tell
  the difference, and that is precisely why the rule is a rule rather than a
  check: the only thing standing between this corpus and a comfortable lie is
  whoever edits it.
- Do not mark a scenario `UE_VERIFIED` in bulk. One at a time, as each is
  actually run.
- Do not present a `NOT_UE_VERIFIED` corpus as certification. F6.5 does not
  close until this corpus does, and F6.6 does not proceed as though it had.

## D-11 in particular

The double-override golden decides D-11 outright. Whatever the reference
produces is what this engine implements, and the contract matrix is updated to
match — not the other way round, and not by intuition about which override
"should" win.

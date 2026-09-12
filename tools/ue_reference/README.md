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

## The harness, and what it is still blocked on

`harness/` is a real project for this, not a description of one. It was built
and run against the installed engine on 2026-09-11, and what follows is
measured rather than planned.

**Unreal Engine 5.7.4 CL 51494982 is installed on this machine** - the version
and changelist the goldens name, at `C:\Program Files\Epic Games\UE_5.7`, with
the GameplayAbilities plugin and its prebuilt binaries. Earlier receipts said it
was not. That was wrong, and correcting it is what turned an open-ended blocker
into a named one.

What was proved to work:

- the editor boots headless and runs Python (`-run=pythonscript`);
- `UAbilitySystemTestAttributeSet` is a shipped, reflected class, and
  `init_stats` registers its sixteen attributes on a component;
- a `FGameplayModifierInfo` can be built exactly, including its evaluation
  channel, by `import_text` with the text Unreal itself exports;
- a `UGameplayEffect` class can be made from a Blueprint asset and its CDO
  edited;
- the game target compiles against real GAS (`ParityHelpers.cpp`,
  `ParityGameInstance.cpp` build clean with MSVC 14.44).

What blocks it, precisely:

| | |
|---|---|
| Editor target | will not build: `SwarmInterface.Build.cs` throws *"Could not find NetFxSDK install dir"*. The .NET Framework 4.6+ SDK is not installed - no `Windows Kits\NETFXSDK`, no `Microsoft SDKs\NETFXSDK` registry key. |
| Game target | builds and links, and cannot run: a monolithic binary needs cooked content, and cooking needs the editor. |
| Python alone | cannot reach `UAbilitySystemComponent::InitAbilityActorInfo`, which is not a `UFUNCTION`; every apply path dereferences `AbilityActorInfo` and the process dies on `Ensure condition failed: AbilityActorInfo.IsValid()` at `AbilitySystemComponent.cpp:476`. |

So one component closes all three: install the **.NET Framework 4.8 SDK** (the
Visual Studio Installer component `Microsoft.Net.Component.4.8.SDK`, or
Microsoft's standalone Developer Pack). With it the editor target builds,
`ParityHelpers` exposes the initialiser, and `python_harness.py` already has the
rest.

The engine install is deliberately not modified. Editing
`SwarmInterface.Build.cs` to stop it throwing would also work and would change
nothing about GameplayEffect arithmetic - and it would mean these goldens were
produced on an engine that is not the stock one they name.

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

---
title: What the Composer Can Draw
sidebar_position: 3
description: The GDScript subset the Composer draws, how everything else is kept, the waiting rule, and the comments the Composer reserves.
---

# What the Composer Can Draw

The Composer edits one method: `_activate_ability()`. Everything else in the script - exports, constants, helper functions, other overrides, comments at the top - is never rewritten.

Inside that method it draws a deliberately small subset of GDScript. Anything outside the subset is **kept**: it stays in the file exactly as written and runs where it is.

## Statements that are drawn

| Statement | Example |
|---|---|
| A call, bare, on a receiver or on a class | `commit_ability()` · `owner_asc.add_tag(&"State.Charging")` |
| A local with a written type | `var aim: GameplayAbilityTargetData = get_activation_target_data()` |
| An assignment to a local or a property | `charge = 0.0` |
| `await` on a signal, or on a task through `.completed()` | `await wait_delay(0.5).completed()` · `await pick.completed()` |
| `if` / `elif` / `else` | `if not commit_ability().is_ok():` |
| `match`, with arms that are one name, one literal value, or `_` | `match stance:` / `Stance.LOW:` / `_:` |
| `return` | `return true` |
| `super()` | `super()` |
| `pass` | `pass` |

Comments and blank lines are kept with the statement below them, and written back where they were.

A statement may be wrapped across several lines; it is still one card.

## Kept regions

A statement the Composer does not draw becomes a **kept region**: one card that stands for the region, takes an execution cable in and hands one on, and cannot be edited. The file keeps it byte for byte, and the Output panel says why:

| Written | Reason given |
|---|---|
| `for`, `while` | A loop has no single place on a canvas. The whole loop, body included, is one region. |
| An inline `func(…)` or `lambda` | An inline function is code the graph cannot show. |
| `breakpoint`, `assert(…)` | A debugger statement or an assertion has no node. |
| `continue`, `break` | Loop keywords. |
| `var level := 1.0` | A local's type must be written: the canvas shows the type of every value. |
| A `match` arm with an array, a dictionary, several values or a binding | A match arm here is one name, one written-out value, or `_`. |

Everything around a kept region stays editable. Move the region's contents into a helper method of the same script, call the helper from `_activate_ability()`, and the call is drawn.

## Waiting correctly

GDScript's `await` waits for a signal or a coroutine. A task is neither, so awaiting the call that returns it does not wait:

```gdscript
	await wait_delay(1.5)               # does not wait - gas.await_without_waiting
	await wait_delay(1.5).completed()   # waits
```

When you need the task's result, keep the task in a typed local and await its `completed()`:

```gdscript
	var pick: AbilityTaskWaitTargetData = wait_target_data()
	await pick.completed()
	apply_effect_to_targets(blast, pick.target_data)
```

See [Ability tasks](../abilities/ability-tasks.md) for why `completed()` rather than `finished`.

## Abilities with no body of their own

An ability that inherits `_activate_ability()` from a base class and only overrides hooks - `_perform()`, `_payload()` - has nothing of its own to draw, and opens read-only. Open the base class to edit the shared body, or give the ability its own `_activate_ability()`.

## Reserved comments

The Composer writes a few comments into `_activate_ability()`. They never change what runs, and are safe to commit.

| Comment | Written for |
|---|---|
| `# @composer-position` | Where a card is drawn, above its statement. Moves with the statement when you move code by hand. |
| `# @composer-virtual-position` | Where the Entry card is drawn. |
| `if false:` with `# @composer-detached` | Statements disconnected from the flow. Each detached island has its own number. |
| `# @composer-flow-else` / `# @composer-flow-default` | An `else:` or `_:` the Composer wrote to cut a path that used to fall through. |
| `# @composer-flow-stop` | A boundary the Composer wrote to end a path. |

An `if false:`, `else:` or `_:` written **without** a marker is your own code, and the Composer never removes it. Deleting a position comment by hand only means the card is placed automatically next time.

## Writing abilities the Composer reads well

- Give every local a written type.
- Keep a task in a typed local when you need its result; otherwise await `.completed()` on the call.
- Keep loops and inline functions in helper methods and call them.
- Keep `_activate_ability()` in the ability's own script.

The six abilities in `addons/GAS_Engine/reference/` were written by hand in this style, and all of them open in the Composer.

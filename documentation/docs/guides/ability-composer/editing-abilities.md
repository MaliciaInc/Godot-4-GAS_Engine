---
title: Editing Abilities
sidebar_position: 2
description: Putting calls down, editing values, data and execution cables, branches, card and pin menus, saving, undo and every keyboard shortcut.
---

# Editing Abilities

Every edit in the Composer is a change to the ability's GDScript. Each gesture is written, read back and checked before it is accepted, and each is one step to undo. A gesture that cannot be expressed in the file is refused with its reason, and the file is left exactly as it was.

## Putting a call down

| Gesture | Writes the call |
|---|---|
| Click a call in the **palette** | After the selected card, or at the end of the body - before its final `return` - when nothing is selected. |
| Drag a call from the palette onto a **card** | After that card. |
| Drag a call onto **empty canvas** | At the end of the body, where you dropped it. |
| **Space**, type, **Enter** | The **finder**: search every call by its name or group. Arrow keys move through the matches; **Escape** closes. |
| **Right-click** empty canvas | The action menu, with the whole catalog and a **Search calls** box. |
| Drag a cable out of a pin and let go over empty canvas | The action menu, offering **only** calls that fit that pin. |

A call is written with every argument filled in - the method's default where it declares one, the type's zero value otherwise - so the new line always compiles. A call that returns a task is written waiting on it:

```gdscript
	await wait_delay(0.0).completed()
```

### Creating a call from a pin

Dragging from a pin into empty canvas and picking a call writes the call **and** the cable, as one change:

| Dragged from | The new call is written |
|---|---|
| A **value output** | After the card that produces the value, taking it as an argument. |
| An **argument** | Before the card that needs it, stored in a new typed local that feeds the argument. |

A value is always written before it is read. A call stored this way gets a local named after the method - `get_activation_target_data_result`, then `…_result_2`:

```gdscript
	var get_activation_target_data_result: GameplayAbilityTargetData = get_activation_target_data()
	apply_effect_to_targets(null, get_activation_target_data_result)
```

## Editing values

Select a card and edit its values in the card's rows or in the **Inspector**; both use the same control. The control depends on the argument's type and on what the file holds:

| The argument holds | Edited with |
|---|---|
| A `bool` | A checkbox. |
| An `int` with an enum hint | A list of the enum's values. |
| An `int` or a `float` | A number box. |
| A vector | One box per component. |
| A `Color` | A colour picker. |
| A resource that is empty or a `preload("…")` | A resource picker. |
| A `String`, `StringName` or `NodePath` | A text box. |
| Any other expression, such as `pick.strength` | The expression as text. |
| A value arriving on a cable | The cable itself, with a **Disconnect** button. |

An argument that is required and empty reads **not connected**, in red, and the ability reports `gas.missing_argument` until it is filled.

## Data cables

A data cable is drawn when an argument **is** a local declared above it - exactly its name:

```gdscript
	var aim: GameplayAbilityTargetData = get_activation_target_data()
	apply_effect_to_targets(burn, aim)          # a cable from `aim`
	apply_effect_to_targets(burn, aim.copied()) # no cable: `aim` is inside an expression
```

| To | Do |
|---|---|
| Pass a local into an argument | Drag from the local's value output to the argument. The argument is rewritten to the local's name. |
| Unplug an argument | **Disconnect** in the Inspector, **Alt+click** the pin, or **Break Link** in the pin's menu. The argument gets its default value back. |
| Feed several arguments from one local | Drag again. A value output holds any number of cables; an argument holds one. |

A cable must be a legal GDScript assignment: the same type, a subclass into its base class, or an `int` into a `float`. An untyped argument accepts anything. A cable that would not compile cannot be drawn.

## Execution cables

Execution cables are the order of the statements. Changing one changes the order in the file.

| Gesture | Result in the file |
|---|---|
| Connect an execution output to a card's input | The statements are reordered so that card runs next. |
| Cut the only path into some statements | They stay where they are, wrapped in `if false:` with a `# @composer-detached` marker. They no longer run and remain editable. Connecting them again unwraps them. |
| Cut a branch's **True** or **False** path | That path leads nowhere; the other side is unchanged. |
| Cut a path that used to fall through | The Composer writes the boundary - an `else:` or `_:` marked with a `# @composer-flow-…` comment - and removes it again when the path is reconnected. |

Several execution cables arriving at one card are normal: the statement after an `if` / `else` is reached from both sides. Putting a new statement onto such an input is refused, because the Composer cannot know which path you meant - drag from the path itself instead.

### Branches and matches

The Composer draws and rewires `if`, `elif`, `else` and `match`, and their conditions and arm values are edited like any other value. New branches are written in the Code view: add the `if` there, save, and it appears on the canvas.

## Card and pin menus

**Right-click a card:**

| Item | Does | Key |
|---|---|---|
| **Remove** | Deletes the selected statements. | **Delete** |
| **Repeat** | Writes a copy of the selected statements after them. | **Ctrl+D** |
| **Copy** | Puts the selected statements on the clipboard as GDScript, ready to paste into the Script editor. | **Ctrl+C** |

**Ctrl+X** cuts and **Ctrl+V** pastes after the selection. Pasted text goes through the same check as every other edit.

**Right-click a pin:**

| Item | Does |
|---|---|
| **Break Link to *card*** | Removes that one cable. One item per cable, in the order the cards are written. |
| **Break All Connections** | Removes every cable on the pin, as one change. |

**Ctrl+drag** from a pin to another pin facing the same way moves every cable on it:

| From | Result |
|---|---|
| A value output | Every consumer now reads the other value. |
| An argument | The value moves to the other argument; the first gets its default back. |
| An execution pin | The run of control moves, and the statements are reordered to match. |

## Arranging the canvas

| Gesture | Does |
|---|---|
| Drag cards | Moves them. Positions are saved in the file as `# @composer-position` comments above each statement; they never change what runs. |
| **Arrow keys** | Nudge the selection by 1, or by 10 with **Shift**. |
| **Home** | Frames the whole graph. |

## Saving and undo

| Key | Does |
|---|---|
| **Ctrl+S** | Save. The new file is read back and compared with the graph first; a mismatch refuses the save and reports why. |
| **Ctrl+Z** | Undo. |
| **Ctrl+Shift+Z** or **Ctrl+Y** | Redo. |

Undo works over the file's text, 64 steps deep. Every gesture - a drag of four cards, a creation with its cable - is one step.

## Keyboard reference

| Key | Does |
|---|---|
| **Space** | Open the finder. |
| **Ctrl+S** | Save. |
| **Ctrl+Z** / **Ctrl+Shift+Z** / **Ctrl+Y** | Undo / redo / redo. |
| **Delete** | Remove the selection. |
| **Ctrl+C** / **Ctrl+X** / **Ctrl+V** | Copy / cut / paste. |
| **Ctrl+D** | Repeat the selection. |
| **Arrows** (+ **Shift**) | Nudge by 1 (10). |
| **Home** | Frame the graph. |
| **Alt+click** a pin | Break all its cables. |
| **Ctrl+drag** a pin | Move its cables to another pin. |

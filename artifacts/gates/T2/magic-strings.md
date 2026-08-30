# Magic String Gate

- Status: **FAIL**
- Project: `<repo>`
- Source files scanned: 62
- Blocking findings: 36
- Scan issues: 0
- Blocking kinds: colors, repeated, templates
- Configured exclusions: addons/gut/**

## Repeated Literals

- `## @meta_license: MIT` -> `addons/GodotGAS/editor/attribute_set_script_writer.gd:61`, `addons/GodotGAS/gameplay_tag/gameplay_tag_generator.gd:30`
- `--exclude` -> `tooling/gates/duplication-gate.py:298`, `tooling/gates/run_gate.py:33`
- `--list` -> `tooling/gates/run_gate.py:105`, `tooling/verify.ps1:239`
- `@tool` -> `addons/GodotGAS/editor/attribute_set_script_writer.gd:63`, `addons/GodotGAS/gameplay_tag/gameplay_tag_generator.gd:32`
- `class_name` -> `addons/GodotGAS/editor/attribute_set_script_writer.gd:64`, `tooling/gates/lib/duplication_units.py:76`
- `const` -> `addons/GodotGAS/gameplay_tag/gameplay_tag_generator.gd:63`, `tooling/gates/lib/languages.py:153`
- `FAIL` -> `tooling/gates/lib/gate_io.py:352`, `tooling/verify.ps1:135`
- `font_color` -> `addons/GodotGAS/editor/theme/dashboard_theme.gd:24`, `addons/GodotGAS/gameplay_tag/gameplay_tag_editor_property.gd:324`, `addons/GodotGAS/gameplay_tag/gameplay_tag_editor_property.gd:326`
- `git` -> `tooling/gates/lib/gate_io.py:200`, `tooling/verify.ps1:285`
- `line` -> `tooling/gates/lib/duplication_units.py:284`, `tooling/strict_typing_pass.py:59`
- `loc` -> `tooling/gates/loc-gate.py:118`, `tooling/gates/run_gate.py:49`, `tooling/gates/run_gate.py:49`
- `name` -> `addons/GodotGAS/attributes/attribute_set.gd:54`, `addons/GodotGAS/utilities/project_settings.gd:59`, `tooling/gates/lib/gdscript_regions.py:30`
- `normal` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:413`, `addons/GodotGAS/target_data/gameplay_target_hit.gd:36`
- `or_greater` -> `addons/GodotGAS/cues/gameplay_cue_notify.gd:27`, `addons/GodotGAS/effects/gameplay_effect.gd:34`, `addons/GodotGAS/effects/gameplay_effect.gd:39`
- `params` -> `tooling/gates/lib/loc_regions.py:163`, `tooling/gates/loc-gate.py:174`
- `pass` -> `addons/GodotGAS/editor/attribute_set_script_writer.gd:126`, `addons/GodotGAS/editor/attribute_set_script_writer.gd:164`, `tooling/gates/lib/duplication_units.py:76`, `tooling/gates/lib/duplication_units.py:79`
- `PASS` -> `tooling/gates/lib/gate_io.py:353`, `tooling/verify.ps1:40`
- `python` -> `tooling/gates/lib/languages.py:30`, `tooling/verify.ps1:35`
- `res://addons/GodotGAS/attributes/attribute_evaluation_result.gd` -> `addons/GodotGAS/attributes/gameplay_attribute_runtime.gd:26`, `addons/GodotGAS/attributes/gameplay_attribute_runtime.gd:30`, `addons/GodotGAS/effects/gameplay_effect_evaluator.gd:22`, `addons/GodotGAS/effects/gameplay_effect_runtime.gd:19`
- `res://addons/GodotGAS/attributes/attribute_modifier_contribution.gd` -> `addons/GodotGAS/attributes/gameplay_attribute_runtime.gd:27`, `addons/GodotGAS/effects/gameplay_effect_evaluator.gd:23`
- `res://addons/GodotGAS/cues/gameplay_cue_entry.gd` -> `addons/GodotGAS/cues/gameplay_cue_registry.gd:17`, `addons/GodotGAS/managers/gameplay_cue_manager.gd:22`
- `res://addons/GodotGAS/cues/gameplay_cue_notify.gd` -> `addons/GodotGAS/cues/gameplay_cue_pool_bucket.gd:17`, `addons/GodotGAS/managers/gameplay_cue_manager.gd:20`
- `res://addons/GodotGAS/cues/gameplay_cue_params.gd` -> `addons/GodotGAS/abilities/gameplay_ability.gd:16`, `addons/GodotGAS/cues/gameplay_cue_notify.gd:15`, `addons/GodotGAS/effects/gameplay_effect_runtime.gd:21`, `addons/GodotGAS/managers/gameplay_cue_manager.gd:23`
- `res://addons/GodotGAS/cues/gameplay_cue_registry.gd` -> `addons/GodotGAS/godot_gas_plugin.gd:31`, `addons/GodotGAS/managers/gameplay_cue_manager.gd:21`
- `res://addons/GodotGAS/effects/gameplay_effect_evaluator.gd` -> `addons/GodotGAS/components/ability_system_component.gd:79`, `addons/GodotGAS/effects/gameplay_effect_runtime.gd:18`
- `res://addons/GodotGAS/effects/gameplay_effect_spec.gd` -> `addons/GodotGAS/abilities/gameplay_ability.gd:18`, `addons/GodotGAS/components/ability_system_component.gd:80`
- `res://addons/GodotGAS/icons/godot_gas_asc.svg` -> `addons/GodotGAS/abilities/gameplay_ability.gd:13`, `addons/GodotGAS/attributes/attribute_data.gd:21`, `addons/GodotGAS/attributes/attribute_set.gd:19`, `addons/GodotGAS/components/ability_system_component.gd:16`, `addons/GodotGAS/cues/gameplay_cue_entry.gd:11`, `addons/GodotGAS/cues/gameplay_cue_notify.gd:12`, `addons/GodotGAS/cues/gameplay_cue_registry.gd:11`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:11`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:11`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:11`, `addons/GodotGAS/effects/active_gameplay_effect.gd:19`, `addons/GodotGAS/effects/gameplay_effect.gd:9`
- `res://addons/GodotGAS/icons/godot_gas_icon_star.svg` -> `addons/GodotGAS/editor/attribute_icons.gd:18`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:15`
- `res://addons/GodotGAS/icons/godot_gas_tags.svg` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:18`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:14`
- `res://addons/GodotGAS/managers/gameplay_cue_manager.gd` -> `addons/GodotGAS/components/ability_system_component.gd:82`, `addons/GodotGAS/godot_gas_plugin.gd:24`
- `res://addons/GodotGAS/target_data/gameplay_effect_context.gd` -> `addons/GodotGAS/abilities/gameplay_ability.gd:17`, `addons/GodotGAS/components/ability_system_component.gd:81`, `addons/GodotGAS/cues/gameplay_cue_params.gd:16`
- `res://addons/GodotGAS/utilities/project_settings.gd` -> `addons/GodotGAS/editor/attribute_set_compiler.gd:13`, `addons/GodotGAS/editor/attribute_set_drafts.gd:18`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:15`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:20`, `addons/GodotGAS/editor/gameplay_tag_tree.gd:17`, `addons/GodotGAS/editor/theme/dashboard_theme.gd:16`, `addons/GodotGAS/gameplay_tag/gameplay_tag_editor_property.gd:15`, `addons/GodotGAS/gameplay_tag/gameplay_tag_generator.gd:15`, `addons/GodotGAS/gameplay_tag/gameplay_tag_inspector_plugin.gd:20`, `addons/GodotGAS/godot_gas_plugin.gd:30`, `addons/GodotGAS/managers/gameplay_cue_manager.gd:19`
- `return` -> `addons/GodotGAS/editor/attribute_set_script_writer.gd:129`, `tooling/gates/lib/languages.py:146`
- `State Management` -> `addons/GodotGAS/components/ability_system_component.gd:64`, `addons/GodotGAS/effects/gameplay_effect.gd:67`
- `test_*.py` -> `tooling/gates/lib/gate_io.py:82`, `tooling/verify.ps1:260`
- `with` -> `addons/GodotGAS/gameplay_tag/gameplay_tag_generator.gd:54`, `tooling/gates/lib/loc_regions.py:35`

## Repeated Templates

- None

## Hard-coded Colors

- None

## Scan Issues

- None

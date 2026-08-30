# Magic String Gate

- Status: **FAIL**
- Project: `<repo>`
- Source files scanned: 37
- Blocking findings: 53
- Scan issues: 0
- Blocking kinds: colors, repeated, templates
- Configured exclusions: addons/gut/**

## Repeated Literals

- `--fail-on` -> `tooling/gates/lib/gate_io.py:359`, `tooling/verify.ps1:241`, `tooling/verify.ps1:243`
- `--include-tests` -> `tooling/gates/lib/gate_io.py:391`, `tooling/verify.ps1:243`
- `--json-output` -> `tooling/gates/lib/gate_io.py:301`, `tooling/verify.ps1:250`
- `--output` -> `tooling/gates/lib/gate_io.py:300`, `tooling/verify.ps1:249`
- `--project-root` -> `tooling/gates/lib/gate_io.py:297`, `tooling/verify.ps1:234`
- `accent_color` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:229`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:191`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:114`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:198`
- `base` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:283`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:286`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:246`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:249`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:164`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:167`
- `base_color` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:230`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:192`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:115`
- `Collapse Tree` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:172`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:284`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:314`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:275`
- `CollapseTree` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:171`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:283`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:313`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:91`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:281`
- `dark` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:281`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:288`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:244`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:251`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:162`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:169`
- `dark_color_1` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:231`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:193`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:116`
- `Edit` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:314`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:543`
- `Editor` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:229`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:230`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:231`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:191`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:192`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:193`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:329`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:527`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:114`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:115`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:116`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:198`
- `editor_panel_flat_style` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:282`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:245`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:163`
- `editor_panel_flat_style_dark` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:280`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:243`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:161`
- `EditorIcons` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:314`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:315`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:316`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:481`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:482`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:131`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:171`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:283`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:310`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:313`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:436`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:477`
- `Error:` -> `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:256`, `addons/GodotGAS/gameplay_tag/gameplay_tag_editor_property.gd:311`, `addons/GodotGAS/gameplay_tag/gameplay_tag_editor_property.gd:316`
- `Expand Tree` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:311`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:275`
- `ExpandTree` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:310`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:279`
- `FAIL` -> `tooling/gates/lib/gate_io.py:335`, `tooling/verify.ps1:135`
- `font_color` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:527`, `addons/GodotGAS/gameplay_tag/gameplay_tag_editor_property.gd:324`, `addons/GodotGAS/gameplay_tag/gameplay_tag_editor_property.gd:326`, `addons/GodotGAS/utilities/project_settings.gd:218`
- `git` -> `tooling/gates/lib/gate_io.py:183`, `tooling/verify.ps1:290`
- `GodotGAS` -> `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:69`, `addons/GodotGAS/godot_gas_plugin.gd:84`, `addons/GodotGAS/managers/gameplay_cue_manager.gd:33`
- `GodotGAS: Tag Registry not found at` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:324`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:70`
- `header` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:290`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:253`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:171`
- `loc` -> `tooling/gates/loc-gate.py:146`, `tooling/verify.ps1:236`
- `name` -> `addons/GodotGAS/utilities/project_settings.gd:101`, `addons/GodotGAS/utilities/project_settings.gd:115`, `addons/GodotGAS/utilities/project_settings.gd:126`, `addons/GodotGAS/utilities/project_settings.gd:137`, `addons/GodotGAS/utilities/project_settings.gd:153`, `addons/GodotGAS/utilities/project_settings.gd:189`, `addons/GodotGAS/utilities/project_settings.gd:193`, `addons/GodotGAS/utilities/project_settings.gd:197`, `tooling/gates/lib/gdscript_regions.py:30`
- `normal` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:519`, `addons/GodotGAS/target_data/gameplay_ability_target_data.gd:48`
- `panel` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:278`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:287`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:289`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:291`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:241`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:250`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:252`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:254`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:505`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:159`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:168`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:170`
- `panel_type` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:277`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:281`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:283`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:285`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:286`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:288`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:290`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:240`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:244`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:246`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:248`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:249`
- `PASS` -> `tooling/gates/lib/gate_io.py:336`, `tooling/verify.ps1:40`
- `python` -> `tooling/gates/lib/languages.py:30`, `tooling/verify.ps1:35`
- `Remove` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:316`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:482`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:547`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:196`, `addons/GodotGAS/gameplay_tag/gameplay_tag_editor_property.gd:188`
- `res://addons/GodotGAS/icons/godot_gas_asc.svg` -> `addons/GodotGAS/abilities/gameplay_ability.gd:11`, `addons/GodotGAS/attributes/attribute_data.gd:11`, `addons/GodotGAS/attributes/attribute_set.gd:10`, `addons/GodotGAS/components/ability_system_component.gd:9`, `addons/GodotGAS/cues/gameplay_cue_entry.gd:11`, `addons/GodotGAS/cues/gameplay_cue_notify.gd:10`, `addons/GodotGAS/cues/gameplay_cue_registry.gd:11`, `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:11`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:11`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:11`, `addons/GodotGAS/effects/active_gameplay_effect.gd:10`, `addons/GodotGAS/effects/gameplay_effect.gd:9`
- `res://addons/GodotGAS/icons/godot_gas_tags.svg` -> `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:18`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:148`
- `res://addons/GodotGAS/utilities/project_settings.gd` -> `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:15`, `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:15`, `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:15`, `addons/GodotGAS/gameplay_tag/gameplay_tag_editor_property.gd:15`, `addons/GodotGAS/gameplay_tag/gameplay_tag_generator.gd:15`, `addons/GodotGAS/gameplay_tag/gameplay_tag_inspector_plugin.gd:18`, `addons/GodotGAS/godot_gas_plugin.gd:27`, `addons/GodotGAS/managers/gameplay_cue_manager.gd:14`
- `State Management` -> `addons/GodotGAS/components/ability_system_component.gd:47`, `addons/GodotGAS/effects/gameplay_effect.gd:67`
- `tags` -> `addons/GodotGAS/components/ability_system_component.gd:277`, `addons/GodotGAS/components/ability_system_component.gd:285`, `addons/GodotGAS/components/ability_system_component.gd:291`, `addons/GodotGAS/gameplay_tag/gameplay_tag_inspector_plugin.gd:31`
- `target` -> `addons/GodotGAS/components/ability_system_component.gd:138`, `addons/GodotGAS/components/ability_system_component.gd:171`, `addons/GodotGAS/components/ability_system_component.gd:502`, `addons/GodotGAS/components/ability_system_component.gd:547`, `addons/GodotGAS/components/ability_system_component.gd:568`, `tooling/gates/lib/gate_io.py:47`
- `test_*.py` -> `tooling/gates/lib/gate_io.py:65`, `tooling/verify.ps1:265`

## Repeated Templates

- None

## Hard-coded Colors

- `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:141`: `Color(`
- `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:176`: `Color(`
- `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:189`: `Color(`
- `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:209`: `Color(`
- `addons/GodotGAS/editor/dashboard_tabs/attribute_sets_tab.gd:236`: `Color(`
- `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:200`: `Color(`
- `addons/GodotGAS/editor/dashboard_tabs/cue_manager_tab.gd:375`: `Color(`
- `addons/GodotGAS/editor/dashboard_tabs/tag_manager_tab.gd:121`: `Color(`
- `addons/GodotGAS/utilities/project_settings.gd:220`: `#e0e0e0`
- `addons/GodotGAS/utilities/project_settings.gd:221`: `#E0E0E0`
- `addons/GodotGAS/utilities/project_settings.gd:222`: `#ffffff`
- `addons/GodotGAS/utilities/project_settings.gd:223`: `#FFFFFF`

## Scan Issues

- None

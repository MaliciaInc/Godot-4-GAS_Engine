# OP025 — Editor plugin acceptance: known limitation

`docs/Fases/GAS_ENGINE_SANITIZATION_REBRANDING.md` section 29 (OP025) requires an
exact 12-step (A-L) sequence in a real Godot 4.7.2 editor, enabling and disabling
the GAS_Engine plugin across editor restarts to prove that autoload ownership of
`GameplayCueManager` persists correctly and never touches a user-owned autoload.

That literal sequence was not executed. Two temporary consumer projects were
built and every available Godot MCP tool was tried against them:

- `mcp__godot__manage_plugins` (`enable`/`disable`) writes `PluginName/enabled=true`
  under `[editor_plugins]` in `project.godot`. Godot's real plugin loader does not
  recognize this shape — the actual contract is
  `enabled=PackedStringArray("res://addons/<name>/plugin.cfg")`. Calling it does
  not invoke `_enable_plugin()`/`_disable_plugin()`.
- `mcp__godot__game_eval` / `mcp__godot-runtime__run_script` require a running
  *game* instance (`run_project`), which has no `EditorPlugin` machinery at all.
- `mcp__godot__launch_editor` opens a real editor process, but per the
  `godot-runtime` MCP server's own tool description, "the editor cannot be
  controlled programmatically" — there is no available way to interactively
  toggle a plugin checkbox or otherwise drive the real enable/disable transition
  from outside the editor's own UI.

Attempting this did surface one real, pre-existing defect, found and fixed as a
direct result (see commit `0058370`): `ability_system_component.gd` and
`gas_cue_snapshot.gd` resolved the `GameplayCueManager` autoload's node path
through the bare autoload identifier (`GameplayCueManager.AUTOLOAD_NODE_PATH`),
which Godot cannot parse until that identifier's autoload is registered. A
fresh consumer project without the autoload pre-declared failed to parse the
addon the moment the plugin was marked enabled, before `_enable_plugin()` ever
ran to add it. Both sites now resolve the same constant through the
already-preloaded `CueManagerScript` instead, which has no such dependency.

The decision logic OP025 exists to protect — `would_add_cue_manager_autoload()`,
`_autoload_points_to_gas_engine()`, and the persisted-ownership project setting
`GASEngineProjectSettings.owns_cue_manager_autoload()` — is exercised by
`test/unit/test_smoke.gd`'s `test_the_plugin_will_not_claim_an_autoload_the_project_declares`
and `test_plugin_autoload_policy_recognizes_only_the_exact_canonical_path`
(added in commit `0058370`), plus the migration tests added alongside them. What
those tests cannot exercise is the live `_enable_plugin()`/`_disable_plugin()`
callbacks themselves, since the document's own OP025 text explicitly forbids
instantiating `EditorPlugin` inside the headless game tree.

Presented to the project owner directly (2026-09-01), who chose explicitly:
document this as a tooling limitation and proceed to OP026 without the literal
acceptance run, rather than continuing to chase a technical workaround.
Neither of OP025's two named STOP conditions (`STOP_AUTOLOAD_OWNERSHIP_NOT_PERSISTENT`,
`STOP_USER_AUTOLOAD_DELETED`) applies here — this is a tooling-availability gap
in the execution environment, not an observed failure of the plugin's own
ownership logic.

Anyone with access to a real Godot 4.7.2 editor can still run the literal A-L
sequence by hand against a scratch consumer project with `addons/GAS_Engine/`
copied in, following section 29 of the rebrand document verbatim.

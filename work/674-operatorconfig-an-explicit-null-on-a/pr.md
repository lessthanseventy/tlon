OperatorConfig: an explicit null turns a nullable knob off (closes #674)

A nullable knob with a non-nil default (`max_session_hours`, 3) could never be turned off: `put_settings/2` deleted the key on nil and `value/2` read nil as "default".

- `value/2` now uses `Map.fetch`: absent → default; null on a nullable knob → nil (off); valid → value; invalid → default.
- `put_settings/2` writes null for a nullable knob; a nil on a non-nullable knob still deletes the key (back to default). Moduledoc/doc corrected.
- Renderers: the office TUI's settings card already prints null as "off"; the API serves `value: null`.

Checked: new tests in operator_config_test.exs (red first, then green); `menard run check --in server`.

# Settings are a TOML file under ~/.config that agents edit

Havooch's settings move out of `settings.json` in the support folder into one TOML file, `$XDG_CONFIG_HOME/havooch/config.toml` when that variable holds an absolute path, else `~/.config/havooch/config.toml`. The person and their agents set things on purpose in it, and the projects of ADR 0004 live in it. The design follows Shipyard's configuration (`yahyabedirhan/shipyard` at `d2a967a`, its ADR 0001 and `docs/configuration.md`) and Swift Lab's ADR 0016 (`yahyabedirhan/swift-lab` at `ccb82cb`), which copied it.

## Decision

- **The file is the interface.** Agents learn it from the `havooch-mate` skill and a JSON Schema the file names on its `#:schema` line, which `taplo check` applies. Keys are kebab-case, after the maintainer's shared `config.toml` convention.
- **Edits apply live.** The app watches the file and applies a save without a restart. The CLI reads it at every command.
- **A broken edit never blanks the app.** The app keeps the last valid configuration and shows the problem with its line.
- **Agents confirm an edit.** After each reload the app writes its verdict to `config-status.json` in the support folder: accepted, or each problem with its line. `havooch config check` gives the same verdict without the app.
- **The app writes the file only in targeted ways**, so the person's comments survive: creating a missing file from a commented header, appending a `[[projects]]` table (`havooch project new`), appending a version to a project (`havooch project add`). It never rewrites the whole file.
- **The theme is chosen by name** (`theme = "Dimmed"`; unset follows the system appearance). Theme files, the colours themselves, stay out of `config.toml`: the person's own themes live in `~/.config/havooch/themes/`, beside it. Token overrides go away; a person writes a theme that extends a built-in one instead.
- **App state stays apart, in the support folder**: recent videos, playheads, the sidebar width, reviews, content hashes, the outbox. The test: a value someone sets on purpose is configuration; a value that records what happened while the app ran is app state.

## Considered Options

- **Keep `settings.json` and add `projects.json`.** Two formats and two places; agents would need to learn both, and JSON loses comments.
- **One TOML file per project.** The maintainer chose one file, as Shipyard and Swift Lab have, so every project is found in one place.
- **Theme colours inside `config.toml`.** Too long for a file people edit by hand; a theme is its own file and can extend another.

## Consequences

- The schema is a public contract. Changing what a key means needs the `version` key and a migration.
- Unknown keys are warnings in the app and errors in the schema, so a file written for a newer build still loads.
- The Settings window loses what moved into the file. What remains of it is decided in the spec.
- `settings.json` is read once to carry the pinned theme over, then retired.

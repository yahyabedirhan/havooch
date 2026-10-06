# Popular VS Code colour themes

## 1. Question

Which VS Code colour themes are the most used by Marketplace install count, and what are the licence, source repository and canonical palette of each? Goal: pick about 8 themes (about 3 light, 5 dark) for the app to ship as built-in themes. The licence must allow reuse of the colour values.

Date read: 2026-10-05, 14:06 UTC.

## 2. Ranking

Source of every install number: the Marketplace extension query API, read on 2026-10-05 at 14:06 UTC.

```sh
curl -s -X POST 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' \
  -H 'Accept: application/json;api-version=3.0-preview.1' -H 'Content-Type: application/json' \
  -d '{"filters":[{"criteria":[{"filterType":8,"value":"Microsoft.VisualStudio.Code"},{"filterType":5,"value":"Themes"}],"pageNumber":1,"pageSize":80,"sortBy":4,"sortOrder":0}],"flags":256}'
```

Licences come from the repository's `LICENSE` file (read through a clone or the GitHub API) and from the extension manifest's `license` field. Variants come from the manifest's `contributes.themes` (`vs` = light, `vs-dark` = dark). Marketplace page: `https://marketplace.visualstudio.com/items?itemName=<extension id>`.

Rank counts colour themes only. Icon themes and non-theme entries in the "Themes" category are listed after the table.

| Rank | Extension id | Display name | Installs | Licence | Variants (light / dark) | Source |
|---|---|---|---:|---|---|---|
| 1 | `ms-vscode.cpptools-themes` | C/C++ Themes | 60,219,901 | Microsoft custom (`SEE LICENSE IN LICENSE.txt`; GitHub reports NOASSERTION) | 2 / 2 (Visual Studio look) | github.com/microsoft/vscode-cpptools |
| 2 | `GitHub.github-vscode-theme` | GitHub Theme | 20,260,291 | MIT | 4 / 5 (Light Default, Dark Default, Dimmed, HC, Colorblind) | github.com/primer/github-vscode-theme |
| 3 | `zhuangtongfa.Material-theme` | One Dark Pro | 12,796,644 | MIT | 0 / 5 | github.com/Binaryify/OneDark-Pro |
| 4 | `dracula-theme.theme-dracula` | Dracula Theme Official | 11,016,330 | MIT | 0 / 2 | github.com/dracula/visual-studio-code |
| 5 | `akamud.vscode-theme-onedark` | Atom One Dark Theme | 7,365,238 | MIT | 0 / 1 | github.com/akamud/vscode-theme-onedark |
| 6 | `Equinusocio.vsc-material-theme` | Material Theme — Deprecated | 4,290,013 | Proprietary (Vira Theme terms; premium successor) | 2 / 10 | github.com/vira-themes/vira-theme-support |
| 7 | `teabyii.ayu` | Ayu | 4,216,077 | MIT | 2 / 4 (Light, Mirage, Dark) | github.com/ayu-theme/vscode-ayu |
| 8 | `monokai.theme-monokai-pro-vscode` | Monokai Pro | 4,166,479 | Commercial (evaluation only, "may not be redistributed") | 2 / 6 | monokai.pro (no public repo) |
| 9 | `johnpapa.winteriscoming` | Winter is Coming Theme | 3,751,195 | MIT | 2 / 4 | github.com/johnpapa/vscode-winteriscoming |
| 10 | `Equinusocio.vsc-community-material-theme` | Community Material Theme | 3,728,631 | Apache-2.0 (manifest; repo now 404) | 2 / 8 | github.com/material-theme/vsc-community-material-theme (gone) |
| 11 | `sdras.night-owl` | Night Owl (incl. Light Owl) | 3,590,361 | MIT | 2 / 2 | github.com/sdras/night-owl-vscode-theme |
| 12 | `enkia.tokyo-night` | Tokyo Night | 2,959,469 | MIT | 1 / 2 (Night, Storm, Light) | github.com/enkia/tokyo-night-vscode-theme |
| 13 | `azemoh.one-monokai` | One Monokai Theme | 2,952,102 | MIT | 0 / 1 | github.com/azemoh/vscode-one-monokai |
| 14 | `whizkydee.material-palenight-theme` | Palenight Theme | 2,648,493 | MIT | 0 / 4 | github.com/whizkydee/vscode-palenight-theme |
| 15 | `RobbOwen.synthwave-vscode` | SynthWave '84 | 2,555,165 | MIT (repo) | 0 / 1 | github.com/robb0wen/synthwave-vscode |
| 16 | `ahmadawais.shades-of-purple` | Shades of Purple | 2,348,493 | MIT text ("2015-∞"; GitHub reports NOASSERTION) | 0 / 2 | github.com/ahmadawais/shades-of-purple-vscode |
| 17 | `wesbos.theme-cobalt2` | Cobalt2 Theme Official | 1,904,504 | MIT (repo) | 0 / 1 | github.com/wesbos/cobalt2-vscode |
| 18 | `EliverLara.andromeda` | Andromeda | 1,702,456 | MIT (repo) | 0 / 5 | github.com/EliverLara/Andromeda |
| 19 | `tal7aouy.theme` | Theme | 1,621,891 | MIT (repo) | 0 / 4 (One Dark Pro look-alike: Flat, Mix, Darker) | github.com/tal7aouy/theme |
| 20 | `BeardedBear.beardedtheme` | Bearded Theme | 1,517,031 | GPL-3.0 | 7 / 58 | github.com/BeardedBear/bearded-theme |
| 21 | `akamud.vscode-theme-onelight` | Atom One Light Theme | 1,454,310 | MIT | 1 / 0 | github.com/akamud/vscode-theme-onelight |
| 22 | `Catppuccin.catppuccin-vsc` | Catppuccin for VSCode | 1,436,330 | MIT | 1 / 3 (Latte; Frappé, Macchiato, Mocha) | github.com/catppuccin/vscode |
| 23 | `liviuschera.noctis` | Noctis | 1,394,783 | MIT (repo) | 3 / 8 | github.com/liviuschera/noctis |
| 24 | `arcticicestudio.nord-visual-studio-code` | Nord | 1,290,456 | MIT | 0 / 1 | github.com/nordtheme/visual-studio-code |
| 25 | `tinkertrain.theme-panda` | Panda Theme | 1,277,208 | None found | 0 / 1 | github.com/siamak/panda-syntax-vscode |
| 26 | `jdinhlife.gruvbox` | Gruvbox Theme | 1,069,899 | MIT | 3 / 3 | github.com/jdinhify/vscode-theme-gruvbox |
| 27 | `jprestidge.theme-material-theme` | Sublime Material Theme | 1,041,570 | not checked (`SEE LICENSE IN LICENSE.md`) | 1 / 1 | github.com/JarvisPrestidge/vscode-material-theme |
| 28 | `rocketseat.theme-omni` | Omni Theme | 1,014,703 | MIT | 0 / 1 | github.com/getomni/visual-studio-code |

Requested candidates outside the top 80 of the category query (second query by extension name, filterType 7, same date, 14:0x UTC):

| Extension id | Display name | Installs | Licence | Variants (light / dark) | Source |
|---|---|---:|---|---|---|
| `mvllow.rose-pine` | Rosé Pine | 342,066 | MIT | 2 / 4 (Dawn; Main, Moon) | github.com/rose-pine/vscode |
| `qufiwefefwoyn.kanagawa` | Kanagawa | 282,442 | MIT (repo) | 0 / 1 | github.com/barklan/kanagawa.vscode |
| `ryanolsonx.solarized` | Solarized (Marketplace port) | 198,132 | MIT | 2 / 3 | github.com/ryanolsonx/vscode-solarized-theme |
| `sainnhe.everforest` | Everforest | 133,867 | MIT (repo archived) | 1 / 1 | github.com/sainnhe/everforest-vscode |

Not colour themes, so not ranked (installs from the same query): `PKief.material-icon-theme` (icon theme, 35,789,240), `vscode-icons-team.vscode-icons` (icon theme, 24,650,333), `ms-vscode.PowerShell` (language extension that also ships a theme, 22,001,397), `Equinusocio.vsc-material-theme-icons` (icon theme, 5,930,745), `writenothing.no-code` (contributes no theme, 5,832,166), `emmanuelbeziat.vscode-great-icons`, `file-icons.file-icons`, `miguelsolorio.fluent-icons`, `hoovercj.vscode-power-mode`, `be5invis.vscode-icontheme-nomo-dark`, `be5invis.vscode-custom-css`, `tal7aouy.icons`, `miguelsolorio.symbols`, `Catppuccin.catppuccin-vsc-icons`, `PKief.material-product-icons`.

Bundled with VS Code, so not on the Marketplace and not ranked: Dark Modern, Light Modern, Dark+, Light+, Monokai, Solarized Dark, Solarized Light, Abyss, Kimbie Dark, Quiet Light, Red, Tomorrow Night Blue, High Contrast.

## 3. Picks

Eight themes: 5 dark, 3 light. All MIT. Every value below is the exact string in the cited file at the cited commit; an 8-digit hex carries alpha (`#RRGGBBAA`). "—" means the theme does not set the key, so VS Code's default would apply.

| # | Pick | Mode | Rank | Licence |
|---|---|---|---|---|
| 1 | GitHub Dark Default | dark | 2 | MIT |
| 2 | GitHub Light Default | light | 2 | MIT |
| 3 | One Dark Pro | dark | 3 | MIT |
| 4 | Dracula | dark | 4 | MIT |
| 5 | Tokyo Night | dark | 12 | MIT |
| 6 | Catppuccin Mocha | dark | 22 | MIT |
| 7 | Catppuccin Latte | light | 22 | MIT |
| 8 | Atom One Light | light | 21 | MIT |

Alternates with full data in the source files: Ayu Light (`ayu-theme/vscode-ayu` @ `d676974ebb245fa5a7ae4444027f72801017f1b6`, `ayu-light.json`), Light Owl and Night Owl (`sdras/night-owl-vscode-theme` @ `cc291eba7976b20d7c66bde6883c27b902196b07`, `themes/Night Owl-Light-color-theme.json`), Tokyo Night Light (`themes/tokyo-night-light-color-theme.json`).

### 3.1 GitHub Theme: GitHub Dark Default and GitHub Light Default

- Licence: MIT, `LICENSE`, "Copyright (c) 2020 Primer".
- Repo: https://github.com/primer/github-vscode-theme
- Commit: `cd78e5e4e7bcf132a6f428ae0f32264bb1b729cf` (package version 6.3.5, the same as the Marketplace version).
- Source: the repo generates the themes from `src/theme.js` and `src/colors.js` with `@primer/primitives`; it has no built JSON. Values below come from the built files in the published 6.3.5 VSIX: `extension/themes/dark-default.json` and `extension/themes/light-default.json`.
- NOTE: `src/theme.js` sets `editor.selectionBackground` to `alpha(color.accent.fg, 0.2)` and then overrides it with `onlyHighContrast(...)`, so the built Default themes leave it unset.

| Role | VS Code key | Dark Default | Light Default |
|---|---|---|---|
| Editor background | `editor.background` | `#0d1117` | `#ffffff` |
| Sidebar background | `sideBar.background` | `#010409` | `#f6f8fa` |
| Activity bar background | `activityBar.background` | `#0d1117` | `#ffffff` |
| Title bar background | `titleBar.activeBackground` | `#0d1117` | `#ffffff` |
| Panel background | `panel.background` | `#010409` | `#f6f8fa` |
| Widget / popover background | `editorWidget.background` | `#161b22` | `#ffffff` |
| Input background | `input.background` | `#0d1117` | `#ffffff` |
| Border / separator | `panel.border`, `sideBar.border`, `input.border` | `#30363d` | `#d0d7de` |
| Primary text | `foreground` | `#e6edf3` | `#1f2328` |
| Secondary text | `descriptionForeground` | `#7d8590` | `#656d76` |
| Disabled / placeholder | `input.placeholderForeground` | `#6e7681` | `#6e7781` |
| Comment | token `comment` | `#8b949e` | `#6e7781` |
| Line number | `editorLineNumber.foreground` | `#6e7681` | `#8c959f` |
| Selection / list active | `list.activeSelectionBackground` | `#6e768166` | `#afb8c133` |
| List hover | `list.hoverBackground` | `#6e76811a` | `#eaeef280` |
| Accent (focus border) | `focusBorder` | `#1f6feb` | `#0969da` |
| Link / accent text | `textLink.foreground` | `#2f81f7` | `#0969da` |
| Button background | `button.background` | `#238636` | `#1f883d` |
| Button foreground | `button.foreground` | `#ffffff` | `#ffffff` |
| Red | `errorForeground` / token keyword | `#f85149` / `#ff7b72` | `#cf222e` |
| Orange | token `variable` | `#ffa657` | `#953800` |
| Yellow | `notificationsWarningIcon.foreground` | `#d29922` | `#9a6700` |
| Green | `gitDecoration.addedResourceForeground` | `#3fb950` | `#1a7f37` |
| Cyan | `terminal.ansiCyan` | `#39c5cf` | `#1b7c83` |
| Blue | `textLink.foreground` / ANSI blue | `#2f81f7` / `#58a6ff` | `#0969da` |
| Purple | token `entity.name.function` | `#d2a8ff` | `#8250df` |
| Tab active top border (brand coral) | `tab.activeBorderTop` | `#f78166` | `#fd8c73` |

| ANSI | Dark Default | Light Default |
|---|---|---|
| foreground | `#e6edf3` | `#1f2328` |
| black / bright | `#484f58` / `#6e7681` | `#24292f` / `#57606a` |
| red / bright | `#ff7b72` / `#ffa198` | `#cf222e` / `#a40e26` |
| green / bright | `#3fb950` / `#56d364` | `#116329` / `#1a7f37` |
| yellow / bright | `#d29922` / `#e3b341` | `#4d2d00` / `#633c01` |
| blue / bright | `#58a6ff` / `#79c0ff` | `#0969da` / `#218bff` |
| magenta / bright | `#bc8cff` / `#d2a8ff` | `#8250df` / `#a475f9` |
| cyan / bright | `#39c5cf` / `#56d4dd` | `#1b7c83` / `#3192aa` |
| white / bright | `#b1bac4` / `#ffffff` | `#6e7781` / `#8c959f` |

### 3.2 One Dark Pro (variant "One Dark Pro")

- Licence: MIT, `LICENSE.txt`, "Copyright (c) 2013-2022 Binaryify".
- Repo: https://github.com/Binaryify/OneDark-Pro
- Commit: `54c3280b29f2c2ed9751e5ca4e071380b7b42205` (version 3.20.2, the Marketplace version).
- File: `themes/OneDark-Pro.json`.

| Role | VS Code key | Value |
|---|---|---|
| Editor background | `editor.background` | `#282c34` |
| Sidebar background | `sideBar.background` | `#21252b` |
| Activity bar background | `activityBar.background` | `#282c34` |
| Title bar background | `titleBar.activeBackground` | `#282c34` |
| Panel background | `panel.background` | — (status bar `#21252b`) |
| Widget / popover background | `editorWidget.background`, `editorHoverWidget.background` | `#21252b` |
| Input background | `input.background` | `#1d1f23` |
| Border / separator | `panel.border` / `editorGroup.border`, `tab.border` | `#3e4452` / `#181a1f` |
| Primary text | `editor.foreground`, `sideBar.foreground` | `#abb2bf` |
| Strong text | `list.activeSelectionForeground`, `activityBar.foreground` | `#d7dae0` |
| Secondary text | `titleBar.activeForeground`, `statusBar.foreground` | `#9da5b4` |
| Comment | token `comment` | `#7f848e` |
| Line number | `editorLineNumber.foreground` | `#495162` |
| Editor selection | `editor.selectionBackground` | `#67769660` |
| Selection / list active | `list.activeSelectionBackground` | `#2c313a` |
| List hover | `list.hoverBackground` | `#2c313a` |
| Focus border | `focusBorder` | `#3e4452` |
| Brand blue (badge) | `activityBarBadge.background` | `#4d78cc` |
| Cursor | `editorCursor.foreground` | `#528bff` |
| Button background | `button.background` | `#404754` |
| Button foreground | `button.foreground` | — |
| Red | token `variable`, `entity.name.tag` | `#e06c75` |
| Orange | token `constant.numeric` | `#d19a66` |
| Yellow | token `entity.name.type` | `#e5c07b` |
| Green | token `string` | `#98c379` |
| Cyan | token `support.function` | `#56b6c2` |
| Blue | token `entity.name.function`, `textLink.foreground` | `#61afef` |
| Purple | token `keyword` | `#c678dd` |
| Error | `editorError.foreground` | `#c24038` |

| ANSI | Normal | Bright |
|---|---|---|
| background / foreground | `#282c34` / `#abb2bf` | |
| black | `#3f4451` | `#4f5666` |
| red | `#e05561` | `#ff616e` |
| green | `#8cc265` | `#a5e075` |
| yellow | `#d18f52` | `#f0a45d` |
| blue | `#4aa5f0` | `#4dc4ff` |
| magenta | `#c162de` | `#de73ff` |
| cyan | `#42b3c2` | `#4cd1e0` |
| white | `#d7dae0` | `#e6e6e6` |

### 3.3 Dracula (variant "Dracula Theme")

- Licence: MIT, `LICENSE`, "Copyright (c) 2016 Dracula Theme".
- Repo: https://github.com/dracula/visual-studio-code
- Commit: `a08a206f2c8420ba3c05f0e8d01d43b2f933fdf8` (version 2.25.1, the Marketplace version).
- Files: palette and mapping in `src/dracula.yml` (anchors `BG`, `FG`, `SELECTION`, `COMMENT`, `CYAN`, `GREEN`, `ORANGE`, `PINK`, `PURPLE`, `RED`, `YELLOW`, `COLOR0`–`COLOR15`); built `extension/theme/dracula.json` in the 2.25.1 VSIX.

| Role | VS Code key | Value |
|---|---|---|
| Editor background | `editor.background` (BG) | `#282A36` |
| Sidebar background | `sideBar.background` | `#21222C` |
| Activity bar background | `activityBar.background` | `#343746` |
| Title bar background | `titleBar.activeBackground` | `#21222C` |
| Panel background | `panel.background` | `#282A36` |
| Widget / popover background | `editorWidget.background` | `#21222C` |
| Input background | `input.background` | `#282A36` |
| Border / separator | `input.border`, `tab.border`, `dropdown.border` | `#191A21` |
| Accent border | `panel.border`, `editorGroup.border` | `#BD93F9` |
| Primary text | `foreground` (FG) | `#F8F8F2` |
| Secondary / disabled text | `tab.inactiveForeground`, `input.placeholderForeground` (COMMENT) | `#6272A4` |
| Comment | token `comment` | `#6272A4` |
| Selection / list active | `editor.selectionBackground`, `list.activeSelectionBackground` (SELECTION) | `#44475A` |
| List hover | `list.hoverBackground` | `#44475A75` |
| Focus border | `focusBorder` | `#6272A4` |
| Brand accent | `activityBarBadge.background`, `progressBar.background` | `#FF79C6` |
| Button background | `button.background` | `#44475A` |
| Button foreground | `button.foreground` | `#F8F8F2` |
| Red | RED | `#FF5555` |
| Orange | ORANGE | `#FFB86C` |
| Yellow | YELLOW | `#F1FA8C` |
| Green | GREEN | `#50FA7B` |
| Cyan | CYAN | `#8BE9FD` |
| Purple | PURPLE | `#BD93F9` |
| Pink | PINK | `#FF79C6` |
| Blue | — (Dracula has no blue; ANSI blue is PURPLE) | `#BD93F9` |

| ANSI | Normal | Bright |
|---|---|---|
| background / foreground | `#282A36` / `#F8F8F2` | |
| black | `#21222C` | `#6272A4` |
| red | `#FF5555` | `#FF6E6E` |
| green | `#50FA7B` | `#69FF94` |
| yellow | `#F1FA8C` | `#FFFFA5` |
| blue | `#BD93F9` | `#D6ACFF` |
| magenta | `#FF79C6` | `#FF92DF` |
| cyan | `#8BE9FD` | `#A4FFFF` |
| white | `#F8F8F2` | `#FFFFFF` |

### 3.4 Tokyo Night (variant "Tokyo Night")

- Licence: MIT, `LICENSE.txt`, "Copyright (c) 2018-present Enkia".
- Repo: https://github.com/enkia/tokyo-night-vscode-theme
- Commit: `7c0f11eaef322f293621ca7befe462214b7ea468` (version 1.1.2, the Marketplace version).
- File: `themes/tokyo-night-color-theme.json`.

| Role | VS Code key | Value |
|---|---|---|
| Editor background | `editor.background` | `#1a1b26` |
| Sidebar background | `sideBar.background` | `#16161e` |
| Activity bar background | `activityBar.background` | `#16161e` |
| Title bar background | `titleBar.activeBackground` | `#16161e` |
| Panel background | `panel.background` | `#16161e` |
| Widget / popover background | `editorWidget.background`, `menu.background` | `#16161e` |
| Input background | `input.background` | `#14141b` |
| Border / separator | `panel.border`, `sideBar.border`, `editorWidget.border` | `#101014` |
| Input border | `input.border` | `#0f0f14` |
| Primary text (editor) | `editor.foreground` | `#a9b1d6` |
| Bright text (variables) | token `variable` | `#c0caf5` |
| UI text | `foreground`, `sideBar.foreground` | `#787c99` |
| Secondary text | `descriptionForeground` | `#515670` |
| Disabled | `disabledForeground` | `#545c7e` |
| Comment | token `comment` | `#51597d` |
| Line number | `editorLineNumber.foreground` | `#363b54` |
| Editor selection | `editor.selectionBackground` | `#515c7e4d` |
| Selection / list active | `list.activeSelectionBackground` | `#202330` |
| List hover | `list.hoverBackground` | `#13131a` |
| Focus border | `focusBorder` | `#545c7e33` |
| Accent | `progressBar.background`, `activityBarBadge.background` | `#3d59a1` |
| Button background | `button.background` | `#3d59a1dd` |
| Button foreground | `button.foreground` | `#ffffff` |
| Red | token `entity.name.tag` | `#f7768e` |
| Orange | token `constant.numeric` | `#ff9e64` |
| Yellow | token `variable.parameter`, `editorWarning.foreground` | `#e0af68` |
| Green | token `string` | `#9ece6a` |
| Teal | `terminal.ansiGreen` | `#73daca` |
| Cyan | `terminal.ansiCyan` / token `keyword.operator` | `#7dcfff` / `#89ddff` |
| Blue | token `entity.name.function` | `#7aa2f7` |
| Purple | token `keyword` | `#bb9af7` |
| Error | `editorError.foreground` | `#db4b4b` |

| ANSI | Normal | Bright |
|---|---|---|
| background / foreground | `#16161e` / `#787c99` | |
| black | `#363b54` | `#363b54` |
| red | `#f7768e` | `#f7768e` |
| green | `#73daca` | `#73daca` |
| yellow | `#e0af68` | `#e0af68` |
| blue | `#7aa2f7` | `#7aa2f7` |
| magenta | `#bb9af7` | `#bb9af7` |
| cyan | `#7dcfff` | `#7dcfff` |
| white | `#787c99` | `#acb0d0` |

### 3.5 Catppuccin: Mocha (dark) and Latte (light)

- Licence: MIT, `LICENSE`, "Copyright (c) 2021 Catppuccin".
- Repo: https://github.com/catppuccin/vscode
- Commit: `befc9e6fc41980f4241408f7049755d47c06ff45` (`packages/catppuccin-vsc` version 3.19.0, the Marketplace version).
- Files: mapping in `packages/catppuccin-vsc/src/theme/uiColors.ts` and `src/theme/tokenColors.ts`; palette from the `@catppuccin/palette` dependency, `palette.json` in https://github.com/catppuccin/palette at `07d02aa110ef9eb7e7427afca5c73ba9cf7f8ebd`; built `extension/themes/mocha.json` and `latte.json` in the 3.19.0 VSIX.

Base palette (`palette.json`):

| Name | Mocha | Latte |
|---|---|---|
| rosewater | `#f5e0dc` | `#dc8a78` |
| flamingo | `#f2cdcd` | `#dd7878` |
| pink | `#f5c2e7` | `#ea76cb` |
| mauve | `#cba6f7` | `#8839ef` |
| red | `#f38ba8` | `#d20f39` |
| maroon | `#eba0ac` | `#e64553` |
| peach | `#fab387` | `#fe640b` |
| yellow | `#f9e2af` | `#df8e1d` |
| green | `#a6e3a1` | `#40a02b` |
| teal | `#94e2d5` | `#179299` |
| sky | `#89dceb` | `#04a5e5` |
| sapphire | `#74c7ec` | `#209fb5` |
| blue | `#89b4fa` | `#1e66f5` |
| lavender | `#b4befe` | `#7287fd` |
| text | `#cdd6f4` | `#4c4f69` |
| subtext1 | `#bac2de` | `#5c5f77` |
| subtext0 | `#a6adc8` | `#6c6f85` |
| overlay2 | `#9399b2` | `#7c7f93` |
| overlay1 | `#7f849c` | `#8c8fa1` |
| overlay0 | `#6c7086` | `#9ca0b0` |
| surface2 | `#585b70` | `#acb0be` |
| surface1 | `#45475a` | `#bcc0cc` |
| surface0 | `#313244` | `#ccd0da` |
| base | `#1e1e2e` | `#eff1f5` |
| mantle | `#181825` | `#e6e9ef` |
| crust | `#11111b` | `#dce0e8` |

UI roles (built theme):

| Role | VS Code key | Mocha | Latte |
|---|---|---|---|
| Editor background | `editor.background` (base) | `#1e1e2e` | `#eff1f5` |
| Sidebar background | `sideBar.background` (mantle) | `#181825` | `#e6e9ef` |
| Activity bar background | `activityBar.background` (crust) | `#11111b` | `#dce0e8` |
| Title bar background | `titleBar.activeBackground` (crust) | `#11111b` | `#dce0e8` |
| Panel background | `panel.background` (base) | `#1e1e2e` | `#eff1f5` |
| Widget / popover background | `editorWidget.background` (mantle) | `#181825` | `#e6e9ef` |
| Input background | `input.background` (surface0) | `#313244` | `#ccd0da` |
| Border / separator | `panel.border`, `editorGroup.border` (surface2) | `#585b70` | `#acb0be` |
| Primary text | `foreground` (text) | `#cdd6f4` | `#4c4f69` |
| Secondary text | `panelTitle.inactiveForeground` | `#a6adc8` | `#6c6f85` |
| Disabled | `disabledForeground` | `#a6adc8` | `#6c6f85` |
| Inactive tab text | `tab.inactiveForeground` (overlay0) | `#6c7086` | `#9ca0b0` |
| Comment | token `comment` (overlay2) | `#9399b2` | `#7c7f93` |
| Line number | `editorLineNumber.foreground` (overlay1) | `#7f849c` | `#8c8fa1` |
| Editor selection | `editor.selectionBackground` | `#9399b240` | `#7c7f934d` |
| Selection / list active | `list.activeSelectionBackground` (surface0) | `#313244` | `#ccd0da` |
| List hover | `list.hoverBackground` | `#31324480` | `#ccd0da80` |
| Accent | `focusBorder`, `button.background` (mauve) | `#cba6f7` | `#8839ef` |
| Button foreground | `button.foreground` (crust) | `#11111b` | `#dce0e8` |
| Link | `textLink.foreground` (blue) | `#89b4fa` | `#1e66f5` |
| Red | `errorForeground` | `#f38ba8` | `#d20f39` |
| Orange (peach) | `editorWarning.foreground` | `#fab387` | `#fe640b` |
| Yellow | token `entity.name.type` | `#f9e2af` | `#df8e1d` |
| Green | `gitDecoration.addedResourceForeground` | `#a6e3a1` | `#40a02b` |
| Cyan (teal / sky) | token `keyword.operator` / sky | `#94e2d5` / `#89dceb` | `#179299` / `#04a5e5` |
| Blue | `editorInfo.foreground` | `#89b4fa` | `#1e66f5` |
| Purple (mauve) / pink | token `keyword` / pink | `#cba6f7` / `#f5c2e7` | `#8839ef` / `#ea76cb` |

| ANSI | Mocha normal / bright | Latte normal / bright |
|---|---|---|
| foreground | `#cdd6f4` | `#4c4f69` |
| black | `#45475a` / `#585b70` | `#5c5f77` / `#6c6f85` |
| red | `#f38ba8` / `#f37799` | `#d20f39` / `#de293e` |
| green | `#a6e3a1` / `#89d88b` | `#40a02b` / `#49af3d` |
| yellow | `#f9e2af` / `#ebd391` | `#df8e1d` / `#eea02d` |
| blue | `#89b4fa` / `#74a8fc` | `#1e66f5` / `#456eff` |
| magenta | `#f5c2e7` / `#f2aede` | `#ea76cb` / `#fe85d8` |
| cyan | `#94e2d5` / `#6bd7ca` | `#179299` / `#2d9fa8` |
| white | `#a6adc8` / `#bac2de` | `#acb0be` / `#bcc0cc` |

### 3.6 Atom One Light

- Licence: MIT, `LICENSE`, "Copyright (c) 2015 Mahmoud Ali".
- Repo: https://github.com/akamud/vscode-theme-onelight
- Commit: `5866e900db932d580e978a58db42f65cde07998b` (version 2.3.0, the Marketplace version).
- File: `themes/OneLight.json`.
- NOTE: the theme sets no `terminal.*` colours. The hues below are its syntax token colours; use them if ANSI colours are needed, and say they are derived.

| Role | VS Code key | Value |
|---|---|---|
| Editor background | `editor.background` | `#FAFAFA` |
| Sidebar background | `sideBar.background` | `#EAEAEB` |
| Activity bar background | `activityBar.background` | `#FAFAFA` |
| Title bar background | `titleBar.activeBackground` | `#EAEAEB` |
| Panel background | `panel.background` | — (status bar `#EAEAEB`) |
| Widget / popover background | `editorWidget.background`, `editorHoverWidget.background` | `#EAEAEB` |
| Input background | `input.background` | `#FFFFFF` |
| Border / separator | `input.border`, `editorGroup.border`, `tab.border` | `#DBDBDC` |
| Widget border | `editorWidget.border` | `#E5E5E6` |
| Primary text | `editor.foreground` | `#383A42` |
| Strong text | `list.activeSelectionForeground` | `#232324` |
| Secondary text | `titleBar.activeForeground` / token | `#424243` / `#696C77` |
| Comment / disabled | token `comment` | `#A0A1A7` |
| Line number | `editorLineNumber.foreground` | `#9D9D9F` |
| Editor selection | `editor.selectionBackground` | `#E5E5E6` |
| Selection / list active | `list.activeSelectionBackground` | `#DBDBDC` |
| List hover | `list.hoverBackground` | `#DBDBDC66` |
| Accent | `focusBorder`, `activityBarBadge.background`, `editorCursor.foreground` | `#526FFF` |
| Button background | `button.background` | `#5871EF` |
| Button foreground | `button.foreground` | `#FFFFFF` |
| Red | token `variable`, `entity.name.tag` | `#E45649` |
| Dark red | token | `#CA1243` |
| Orange | token `constant.numeric` | `#986801` |
| Yellow | token `entity.name.type` | `#C18401` |
| Green | token `string` | `#50A14F` |
| Cyan | token `support.function` | `#0184BC` |
| Blue | token `entity.name.function` | `#4078F2` |
| Purple | token `keyword` | `#A626A4` |

### 3.7 How the picks map onto Havooch's tokens

The files are `Packaging/Themes/<name>.json`, credited in `Packaging/Themes/NOTICE.md`. Each one sets every token but `letterbox`, `popoverBorder`, `well`, `knob`, `shadow`, `controlHover`, `regionDim` and `sizeLabel`, which come from the default theme of its kind.

0.2.0 put the whole window on `window` and removed `stage`, `bar`, `sidebar`, `sidebarSection`, `sidebarRowHover`, `sidebarRowSelected` and `header` (`docs/low-level-design.md`, L36), and later `controlPressed`, which no view drew (L43). The files keep the editor background on `window`; the rows below for the removed tokens are the 0.1.0 mapping.

| Token | Taken from |
|---|---|
| `window`, `stage` (0.1.0) | editor background |
| `bar`, `sidebar` (0.1.0) | side bar background |
| `header` (0.1.0) | title bar background |
| `popover`, `notice` | widget background, or a palette surface where the widget is the side bar's colour |
| `field` | input background (white in the light themes) |
| `track`, `separator` | border colour |
| `textPrimary`, `textSecondary`, `textTertiary` | foreground, description foreground, comment or disabled foreground |
| `accent`, `regionOutline`, `badge` | the theme's brand colour: blue (GitHub, One Dark Pro, Tokyo Night, Atom One Light), purple (Dracula), mauve (Catppuccin) |
| `textOnAccent`, `badgeText` | the darkest background in dark themes, white in light themes |
| `agent`, `question`, `control` | the theme's blue, cyan or teal, and yellow |
| `bubble*` (and `sidebarSection`, `sidebarRow*` in 0.1.0) | the colours above over the side bar, mixed to an opaque colour |
| states | queued: comment grey; sent: a second neutral or the theme's purple; acknowledged: blue; working: yellow; done: green; failed: red |

Where a palette colour failed the readability test (`everyThemeReads` in `Tests/ReviewStoreTests/ThemeFilesTests.swift`) or the no-pink rule for states, the file uses another one:

- **Catppuccin Mocha:** failed is peach `#fab387`, since red `#f38ba8` is pink by the app's rule.
- **Catppuccin Latte:** failed is maroon `#e64553`, since red `#d20f39` is pink by the rule. Working is `#ae6f17`, yellow `#df8e1d` darkened so a white glyph reads on it.
- **Tokyo Night:** failed is orange `#ff9e64`, since red `#f7768e` is pink by the rule.
- **Dracula:** secondary text is `#a6aec7`, foreground mixed 45 % into comment `#6272a4`, since the comment colour is too faint for secondary text. No state is pink `#ff79c6`.
- **Atom One Light:** secondary text is `#555862`, `#696c77` mixed toward `#383a42`, for 4.5:1 on the side bar. Sent is `#383a42`, since purple `#a626a4` is pink by the rule.
- **GitHub Dark:** accent is ANSI blue `#58a6ff`, not the focus border `#1f6feb`, so a dark glyph reads on it.
- **One Dark Pro:** primary text is `#d7dae0`, since the editor foreground `#abb2bf` is below 7:1.

## 4. Why the others were left out

- C/C++ Themes (rank 1): a copy of the Visual Studio look; Microsoft custom licence, not MIT-style.
- Material Theme (rank 6): now proprietary. The 34.7.16 licence is the "Terms & Conditions for Vira Theme" (a revocable licence), and the readme sells Vira Theme as the "premium" successor. Community Material Theme (rank 10) is Apache-2.0 per its manifest, but its repo is gone (404), so the source cannot be checked at a commit.
- Monokai Pro (rank 8): commercial. The licence allows evaluation only and says it "may not be sub-licensed, resold, or redistributed".
- Atom One Dark (rank 5), `tal7aouy.theme` (rank 19) and One Monokai (rank 13): duplicate the One Dark look already covered by One Dark Pro.
- Ayu (rank 7) and Night Owl / Light Owl (rank 11): MIT and popular; kept as alternates. Ayu Light uses orange `#f29718` as its accent and a grey UI text `#828e9f`; Night Owl's deep navy overlaps Tokyo Night.
- Winter is Coming (rank 9), Palenight (rank 14), Cobalt2 (rank 17), Noctis (rank 23), Nord (rank 24), Gruvbox (rank 26), Omni (rank 28): MIT but fewer installs than the picks in the same mood, or a blue/purple-dark look the picks already cover.
- SynthWave '84 (rank 15), Shades of Purple (rank 16), Andromeda (rank 18): neon or purple/pink-heavy; SynthWave's glow needs CSS injection. Shades of Purple's licence file is an MIT text with a non-standard year ("2015-∞").
- Bearded Theme (rank 20): GPL-3.0, so reuse carries copyleft terms.
- Panda (rank 25): no licence file found.
- Sublime Material Theme (rank 27): licence not checked; old (last updated 2016).
- Rosé Pine (342,066), Kanagawa (282,442), Solarized port (198,132), Everforest (133,867): MIT but far fewer Marketplace installs. Solarized Light/Dark are bundled with VS Code. The Everforest repo is archived.

## 5. Sources

- Marketplace extension query API, `https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery`, read 2026-10-05 14:06 UTC: category "Themes" sorted by install count (flags 256), and a by-name query (filterType 7, flags 0x1|0x2|0x80|0x100|0x200) for manifests, licences and VSIX packages.
- Extension manifests (`Microsoft.VisualStudio.Code.Manifest` asset) and licence assets (`Microsoft.VisualStudio.Services.Content.License`) for Material Theme 34.7.16, Monokai Pro 2.0.16, Winter is Coming 1.5.0 and Night Owl 2.1.1.
- Published VSIX packages: GitHub Theme 6.3.5, Dracula 2.25.1, Catppuccin 3.19.0.
- Clones in `~/Developer/open-source/`:
  - primer/github-vscode-theme @ `cd78e5e4e7bcf132a6f428ae0f32264bb1b729cf`
  - Binaryify/OneDark-Pro @ `54c3280b29f2c2ed9751e5ca4e071380b7b42205`
  - dracula/visual-studio-code @ `a08a206f2c8420ba3c05f0e8d01d43b2f933fdf8`
  - akamud/vscode-theme-onelight @ `5866e900db932d580e978a58db42f65cde07998b`
  - enkia/tokyo-night-vscode-theme @ `7c0f11eaef322f293621ca7befe462214b7ea468`
  - catppuccin/vscode @ `befc9e6fc41980f4241408f7049755d47c06ff45`
  - sdras/night-owl-vscode-theme @ `cc291eba7976b20d7c66bde6883c27b902196b07`
  - ayu-theme/vscode-ayu @ `d676974ebb245fa5a7ae4444027f72801017f1b6`
- catppuccin/palette `palette.json` @ `07d02aa110ef9eb7e7427afca5c73ba9cf7f8ebd` (GitHub API).
- GitHub API `repos/<owner>/<repo>` and `repos/<owner>/<repo>/license` for the licences of the other ranked themes.

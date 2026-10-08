# Filled controls use an accentFill token that white text reads on

The app tints its window with the theme's `accent` (`RootView`), and native prominent buttons draw white text on their tint. In Default Dark the accent is a light blue (`#9db6dd`), so white text on Send, "Open a Video…" and Save reads at about 1.9:1; Default Light's `#5b7db1` reads at about 4.2:1, under the 4.5:1 minimum. Themes with light accents (Catppuccin Mocha, Dracula, Tokyo Night, GitHub Dark) have the same problem. The maintainer rejected the low contrast in the onboarding prototypes.

## Decision

- A new theme token, **`accentFill`**, is the fill of filled controls. White text on it reads at 4.5:1 or more.
- Every bundled theme gives `accentFill` a value that passes; Default Light and Default Dark use `#48689D` (about 5.6:1).
- Filled controls (native prominent buttons and the app's own filled buttons) use `accentFill`. `accent` stays for lines, selections, rings and pins, where no text sits on it.
- A test checks every bundled theme's `accentFill` against white for 4.5:1, so a new theme cannot break it.

## Considered Options

- **Dark text on the light accent (`textOnAccent`).** Default Dark already defines it, but native prominent buttons ignore it, and every filled control would need a custom style.
- **Darken `accent` itself.** It would change every line, ring and selection in every theme.

## Consequences

- A theme file without `accentFill` falls back to a value derived from `accent` that passes the contrast test.

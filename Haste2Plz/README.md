# Haste2Plz

Haste2Plz is a small Windower addon for FFXI that prefers Koru-Moru's `Haste II` over regular `Haste`.

## What it does

- Watches your party/alliance for Koru-Moru.
- If Koru-Moru is present and the action packet shows a regular `Haste` cast on you, the addon clears the shared Haste buff.
- It watches the incoming spell action so it can tell Koru-Moru's `Haste II` apart from plain `Haste`.

## Commands

- `//h2p on`: Enable the addon.
- `//h2p off`: Disable the addon.
- `//h2p check`: Run an immediate evaluation.
- `//h2p status`: Show current state.

## Notes

- This addon only clears regular Haste when Koru-Moru is present.
- It uses the incoming action packet because the game shares the same haste buff slot for both versions.
- I have not tested this in-game yet, so the exact buff timing still needs a live sanity check.

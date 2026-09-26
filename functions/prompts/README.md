# AI prompts

The bots' system prompts live in this folder and are **not** committed. Only
this README is tracked. `src/prompts.ts` reads the files at first use, and
`firebase deploy` uploads the whole `functions` folder, so a deployment made
from a machine that has them works unchanged.

Expected files, each holding one prompt as plain text:

| File | Used for |
| --- | --- |
| `framework.md` | Injected wherever a bot's prompt says `{{FRAMEWORK}}` |
| `snack-analyzer.md` | Bot 1, the photo analyzer |
| `swipe-builder.md` | Bot 3, the swipe deck and its summary |
| `idea-generator.md` | Bot 2, the recipe maker |
| `craving-translator.md` | Bot 4, the craving translator |
| `profile-rules.md` | Appended after the person's profile block |

Every bot must answer with bare JSON in the shape the app decodes (see
`Shiphaton App/AI/AIModels.swift`). Without these files every AI call fails
with a clear `failed-precondition` error and the app falls back to its
offline library.

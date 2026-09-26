/**
 * The bots' system prompts, read from `functions/prompts/` at first use.
 *
 * The prompt text is not part of the repository: that directory is
 * gitignored (see its README for the file names). It is still uploaded
 * with every `firebase deploy`, because the deploy packs the whole
 * functions folder, so the deployed code finds it next to `lib/`.
 *
 * Without the files the function answers every AI call with a clear
 * "not configured" error, and the app falls back to its offline library
 * the way it does for any other failed call.
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { HttpsError } from "firebase-functions/v2/https";

type Bot = "snackAnalyzer" | "swipeBuilder" | "ideaGenerator" | "cravingTranslator";

/** Compiled code runs from `lib/`; the prompts sit beside it. */
const PROMPTS_DIR = join(__dirname, "..", "prompts");

const BOT_FILES: Record<Bot, string> = {
  snackAnalyzer: "snack-analyzer.md",
  swipeBuilder: "swipe-builder.md",
  ideaGenerator: "idea-generator.md",
  cravingTranslator: "craving-translator.md",
};

interface Prompts {
  /** Injected wherever a bot's template says `{{FRAMEWORK}}`. */
  framework: string;
  /** How every bot reads the profile block the app sends with each call. */
  profileRules: string;
  bots: Record<Bot, string>;
}

let loaded: Prompts | null = null;

function read(name: string): string {
  return readFileSync(join(PROMPTS_DIR, name), "utf8");
}

function prompts(): Prompts {
  if (loaded) return loaded;
  try {
    loaded = {
      framework: read("framework.md"),
      profileRules: read("profile-rules.md"),
      bots: {
        snackAnalyzer: read(BOT_FILES.snackAnalyzer),
        swipeBuilder: read(BOT_FILES.swipeBuilder),
        ideaGenerator: read(BOT_FILES.ideaGenerator),
        cravingTranslator: read(BOT_FILES.cravingTranslator),
      },
    };
    return loaded;
  } catch (error) {
    throw new HttpsError(
      "failed-precondition",
      `AI prompts aren't installed on this deployment (${String(error)}).`
    );
  }
}

export function systemPrompt(bot: Bot, profile: string): string {
  const { framework, profileRules, bots } = prompts();
  let prompt = bots[bot].replace("{{FRAMEWORK}}", framework);
  const trimmed = profile.trim();
  if (trimmed) {
    prompt += `\n\n## USER PROFILE (from account settings)\n\n${trimmed}\n\n${profileRules}`;
  }
  return prompt;
}

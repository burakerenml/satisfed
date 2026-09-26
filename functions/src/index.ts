/**
 * comboAI — the single door into Azure OpenAI for the app.
 *
 * The Azure key lives only here (Secret Manager, via `defineSecret`), never
 * in the client. Every call must carry a valid Firebase App Check token
 * (`enforceAppCheck: true`), which Firebase verifies came from a genuine,
 * untampered copy of the app (App Attest on device, debug tokens in dev) —
 * no user sign-in involved.
 */

import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { defineSecret, defineBoolean, defineString } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { timingSafeEqual } from "node:crypto";
import { systemPrompt } from "./prompts";
import { Feature, appUserID, applyWebhookEvent, authorize, closeFreeLoop, readState } from "./entitlements";

const MAX_COMPLETION_TOKENS = 4000;

const azureApiKey = defineSecret("AZURE_OPENAI_API_KEY");
/** The Azure OpenAI resource and the deployment inside it. Both come from
 *  the gitignored `.env.<project>` file (see `.env.example`), so the
 *  repository names neither. */
const azureEndpoint = defineString("AZURE_OPENAI_ENDPOINT");
const azureDeployment = defineString("AZURE_OPENAI_DEPLOYMENT");
/** RevenueCat's v1 secret key, for reading entitlements straight from the
 *  source when the mirror can't answer. Required: without it every id the
 *  webhook has never written passes the gate, and the function logs an
 *  error on every call to say so. */
const revenueCatSecretKey = defineSecret("REVENUECAT_SECRET_KEY");
/** The value RevenueCat is told to send in the webhook's Authorization
 *  header. Anything else is dropped. */
const revenueCatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");
/** Set false to run the gate in report-only mode: the ledger still fills
 *  in and the app still offers the paywall, but nothing is refused. Useful
 *  for the first deploy, before the webhook has been seen working. */
const paywallEnforce = defineBoolean("PAYWALL_ENFORCE", { default: true });

// A distressed message can be blocked by Azure's own content filter before
// the model runs. Answer supportively, never with a raw error.
const SUPPORT_FALLBACK = {
  intro:
    "Thank you for sharing that with me, what you're feeling matters. Just so you know, " +
    "no food ever needs to be earned or made up for, and every food can fit. 💛",
  combos: [] as unknown[],
  coach_note:
    "If food is feeling stressful lately, talking it through with a registered dietitian or " +
    "someone you trust can really help. I'm here whenever you want cozy snack ideas, no judgment, ever.",
  safety_fallback: true,
};

type Bot = "snackAnalyzer" | "swipeBuilder" | "ideaGenerator" | "cravingTranslator";

interface ComboAIRequest {
  bot: Bot;
  // snackAnalyzer
  imageBase64?: string;
  mimeType?: string;
  note?: string;
  // swipeBuilder
  mode?: "DECK" | "SUMMARY";
  payload?: Record<string, unknown>;
  // ideaGenerator
  message?: string;
  // cravingTranslator
  craving?: string;
  userData?: unknown;
  // all bots
  profile?: string;
  /** The UUID the app keeps in the Keychain. The paywall gate is keyed on
   *  it, and it is the same id the app configures RevenueCat with. */
  appUserID?: string;
  /** Sent right after a purchase or restore: skip a "not subscribed"
   *  mirror and ask RevenueCat directly, so the person who just paid is
   *  answered before the webhook has had a chance to land. */
  fresh?: boolean;
}

// The translator's answer when Azure's filter blocks a distressed message.
const CRAVING_SUPPORT_FALLBACK = {
  headline: "Thank you for telling me, what you're feeling matters. 💛",
  signals: [] as unknown[],
  body_needs: ["Kindness, before anything else"],
  body_talk:
    "Cravings are biology, not character. Restriction earlier only makes them louder later. " +
    "No food ever needs to be earned, and every food can fit.",
  often_quiets_it: [] as unknown[],
  worth_knowing: "",
  check_in: "",
  coach_note:
    "If food is feeling stressful lately, talking it through with a registered dietitian or " +
    "someone you trust can really help. I'm here whenever you want, no judgment, ever.",
  safety_fallback: true,
};

async function callAzure(system: string, userContent: unknown): Promise<string> {
  const key = azureApiKey.value();
  const endpoint = azureEndpoint.value().trim().replace(/\/+$/, "");
  const deployment = azureDeployment.value().trim();
  if (!key || !endpoint || !deployment) throw new HttpsError("failed-precondition", "AI isn't configured yet.");

  const response = await fetch(`${endpoint}/openai/v1/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model: deployment,
      max_completion_tokens: MAX_COMPLETION_TOKENS,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: system },
        { role: "user", content: userContent },
      ],
    }),
  });

  const bodyText = await response.text();
  if (!response.ok) {
    if (response.status === 400 && bodyText.includes("content_filter")) {
      throw new HttpsError("invalid-argument", "content_filter");
    }
    logger.error("Azure request failed", { status: response.status, body: bodyText });
    throw new HttpsError("unavailable", `AI request failed (${response.status}).`);
  }

  const top = JSON.parse(bodyText);
  const content = top?.choices?.[0]?.message?.content;
  if (typeof content !== "string") throw new HttpsError("internal", "The AI sent back something we couldn't read.");
  return content;
}

/** The model is instructed to return bare JSON; strips stray fences and any
 *  prose around them defensively, so "Here is the JSON:" followed by a fenced
 *  block still parses instead of costing a whole retry. When that still
 *  fails, one salvage pass clips to the outermost object and drops trailing
 *  commas before a closing brace or bracket, the two mechanical defects the
 *  model actually produces. */
function parseJSON(raw: string): unknown {
  let text = raw.trim();
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced) {
    text = fenced[1].trim();
  } else if (!text.startsWith("{")) {
    text = clipToObject(text);
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    const repaired = clipToObject(text).replace(/,(\s*[}\]])/g, "$1");
    if (repaired === text) throw error;
    return JSON.parse(repaired);
  }
}

function clipToObject(text: string): string {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  return start >= 0 && end > start ? text.slice(start, end + 1) : text;
}

/** callAzure + parse, with one retry: the model occasionally emits
 *  truncated or otherwise invalid JSON, and a second run almost always
 *  lands. Anything but a parse failure propagates immediately. */
async function chatJSON(system: string, userContent: unknown): Promise<unknown> {
  let lastError: unknown;
  for (let attempt = 0; attempt < 2; attempt++) {
    const raw = await callAzure(system, userContent);
    try {
      return parseJSON(raw);
    } catch (error) {
      lastError = error;
      logger.warn("Model returned invalid JSON", { attempt, length: raw.length });
    }
  }
  throw new HttpsError("internal", `The AI sent back something we couldn't read: ${String(lastError)}`);
}

/** The app matches builder names exactly; the model sometimes shortens
 *  "healthy_fats" to "fat" or "fats". Fold every spelling onto the three
 *  strings the app knows, wherever they appear in a deck. */
const BUILDER_ALIASES: Record<string, string> = {
  protein: "protein", proteins: "protein",
  fibre: "fibre", fiber: "fibre",
  healthy_fats: "healthy_fats", healthy_fat: "healthy_fats", "healthy fats": "healthy_fats",
  "healthy fat": "healthy_fats", fats: "healthy_fats", fat: "healthy_fats",
};

function normalizeBuilders(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const out: string[] = [];
  for (const raw of value) {
    if (typeof raw !== "string") continue;
    const mapped = BUILDER_ALIASES[raw.trim().toLowerCase()];
    if (mapped && !out.includes(mapped)) out.push(mapped);
  }
  return out;
}

function normalizeDeck(parsed: unknown): unknown {
  if (!parsed || typeof parsed !== "object") return parsed;
  const deck = parsed as Record<string, unknown>;
  const cards = Array.isArray(deck.cards)
    ? deck.cards.map((card) =>
        card && typeof card === "object"
          ? { ...(card as Record<string, unknown>), compounds: normalizeBuilders((card as Record<string, unknown>).compounds) }
          : card)
    : [];
  return { ...deck, base_compounds: normalizeBuilders(deck.base_compounds), cards };
}

// App Check proves a call came from a genuine build; it says nothing about
// what that build's owner puts in the body. These caps keep the function a
// proxy for the app's four bots rather than a general-purpose model
// endpoint on this project's key. Sizes are generous next to what the app
// sends (a 1200px JPEG at 0.7 quality is well under a megabyte).
const LIMITS = {
  text: 2_000, // craving, note, message
  profile: 3_000,
  imageBase64: 2_500_000,
  payload: 20_000, // JSON.stringify of the swipe payload or the history block
};
const IMAGE_MIME_TYPES = new Set(["image/jpeg", "image/png", "image/heic", "image/webp"]);

/** A string field, trimmed and capped, or "" when absent. Anything but a
 *  string is a malformed request, answered with a clean error instead of a
 *  TypeError further down. */
function text(value: unknown, field: string, max: number): string {
  if (value === undefined || value === null) return "";
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} must be a string.`);
  const trimmed = value.trim();
  if (trimmed.length > max) throw new HttpsError("invalid-argument", `${field} is too long.`);
  return trimmed;
}

/** A JSON-serialisable object, capped by its serialised size. */
function json(value: unknown, field: string, max: number): string {
  const serialised = typeof value === "string" ? value : JSON.stringify(value);
  if (typeof serialised !== "string") throw new HttpsError("invalid-argument", `${field} must be JSON.`);
  if (serialised.length > max) throw new HttpsError("invalid-argument", `${field} is too large.`);
  return serialised;
}

/** Which feature a bot belongs to, for the free-loop ledger. The photo
 *  read and the swipe deck are two calls of one flow. */
function featureOf(bot: unknown): Feature {
  switch (bot) {
    case "ideaGenerator": return "ideas";
    case "cravingTranslator": return "cravings";
    default: return "plates";
  }
}

export const comboAI = onCall<ComboAIRequest>(
  {
    // The app carries no Google identity either; App Check is the door.
    // Without this Cloud Run answered 403 before the code ran, exactly
    // as it did for the webhook.
    invoker: "public",
    enforceAppCheck: true,
    secrets: [azureApiKey, revenueCatSecretKey],
    cpu: 1,
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    const data = request.data;
    if (!data || typeof data !== "object") throw new HttpsError("invalid-argument", "Missing request body.");
    const profile = text(data.profile, "profile", LIMITS.profile);

    // Nothing reaches Azure before this. App Check proved the call came
    // from a real copy of the app; this proves the person on the other end
    // is either subscribed or still holding their one free loop. Throws
    // PAYWALL_REQUIRED when they are neither.
    const id = appUserID(data.appUserID);
    const gate = await authorize(id, {
      feature: featureOf(data.bot),
      isVision: data.bot === "snackAnalyzer",
      enforce: paywallEnforce.value(),
      secretKey: revenueCatSecretKey.value(),
      fresh: data.fresh === true,
    });

    switch (data.bot) {
      case "snackAnalyzer": {
        if (typeof data.imageBase64 !== "string" || !data.imageBase64) {
          throw new HttpsError("invalid-argument", "Missing imageBase64.");
        }
        if (data.imageBase64.length > LIMITS.imageBase64) throw new HttpsError("invalid-argument", "Photo is too large.");
        if (!/^[A-Za-z0-9+/=\r\n]+$/.test(data.imageBase64)) throw new HttpsError("invalid-argument", "Photo isn't base64.");
        const mimeType = data.mimeType ?? "image/jpeg";
        if (!IMAGE_MIME_TYPES.has(mimeType)) throw new HttpsError("invalid-argument", "Unsupported image type.");
        const dataURL = `data:${mimeType};base64,${data.imageBase64}`;
        const content = [
          { type: "text", text: text(data.note, "note", LIMITS.text) || "Here is my snack!" },
          { type: "image_url", image_url: { url: dataURL } },
        ];
        return chatJSON(systemPrompt("snackAnalyzer", profile), content);
      }

      case "swipeBuilder": {
        if (data.mode !== "DECK" && data.mode !== "SUMMARY") throw new HttpsError("invalid-argument", "Unknown mode.");
        if (!data.payload || typeof data.payload !== "object") throw new HttpsError("invalid-argument", "Missing payload.");
        const userContent = `MODE: ${data.mode}\n${json(data.payload, "payload", LIMITS.payload)}`;
        const parsed = await chatJSON(systemPrompt("swipeBuilder", profile), userContent);
        if (data.mode === "DECK") return normalizeDeck(parsed);
        // The summary is the payoff and so the natural end of the free
        // loop. It closes only now, once the summary has actually been
        // produced: a loop closed before an Azure failure would leave the
        // person with a paywall and no summary to show for it.
        if (gate.pro === "free") await closeFreeLoop(id);
        return parsed;
      }

      case "ideaGenerator": {
        const message = text(data.message, "message", LIMITS.text);
        if (!message) throw new HttpsError("invalid-argument", "Missing message.");
        let ideas: unknown;
        try {
          ideas = await chatJSON(systemPrompt("ideaGenerator", profile), message);
        } catch (error) {
          if (!(error instanceof HttpsError && error.message === "content_filter")) throw error;
          ideas = SUPPORT_FALLBACK;
        }
        // One answer is the whole free go. Closed only now, once there is
        // an answer to show for it, same as the plate summary.
        if (gate.pro === "free") await closeFreeLoop(id);
        return ideas;
      }

      case "cravingTranslator": {
        // Craving + optional context (mood, last meal) + the person's own
        // logged history, which the prompt mines for patterns. Reasoning
        // models ignore temperature, so a seed in the message is what
        // keeps two reads of the same craving from coming out identical.
        const craving = text(data.craving, "craving", LIMITS.text);
        if (!craving) throw new HttpsError("invalid-argument", "Missing craving.");
        let message = craving;
        const note = text(data.note, "note", LIMITS.text);
        if (note) message += `\nContext: ${note}`;
        if (data.userData) {
          message += `\nRECENT DATA: ${json(data.userData, "userData", LIMITS.payload)}`;
        }
        message += `\nVARIETY SEED: ${1000 + Math.floor(Math.random() * 9000)}`;
        let read: unknown;
        try {
          read = await chatJSON(systemPrompt("cravingTranslator", profile), message);
        } catch (error) {
          if (!(error instanceof HttpsError && error.message === "content_filter")) throw error;
          read = CRAVING_SUPPORT_FALLBACK;
        }
        // One read is the whole free go.
        if (gate.pro === "free") await closeFreeLoop(id);
        return read;
      }

      default:
        throw new HttpsError("invalid-argument", "Unknown bot.");
    }
  }
);

/**
 * What the app asks before it decides whether to show a paywall.
 *
 * Cheap, App Check gated, and free of side effects on the AI budget. The
 * app calls it on launch, when it comes back to the foreground, after a
 * purchase, and right after a free loop's summary lands — which is what
 * lets the paywall arrive on the good news rather than on an error.
 */
export const entitlementStatus = onCall<{ appUserID?: string; fresh?: boolean }>(
  {
    // Same as `comboAI`: every call from the app was refused at the
    // platform layer ("The request was not authenticated") until this
    // was set, so the app never got the server's answer.
    invoker: "public",
    enforceAppCheck: true,
    secrets: [revenueCatSecretKey],
    cpu: 1,
    memory: "256MiB",
    timeoutSeconds: 20,
  },
  async (request) => {
    const state = await readState(
      appUserID(request.data?.appUserID),
      revenueCatSecretKey.value(),
      request.data?.fresh === true
    );
    return {
      // "unknown" means we couldn't reach RevenueCat. The gate fails open
      // in that case, so the app should too: no paywall on a bad network.
      // The app reads `proState` to tell "paid" from "couldn't check";
      // `pro` stays for anything still reading the older shape.
      pro: state.pro !== "free",
      proState: state.pro,
      freeLoop: state.freeLoop,
    };
  }
);

/**
 * RevenueCat's webhook. Configure it in the dashboard with this function's
 * URL and an Authorization header matching REVENUECAT_WEBHOOK_SECRET.
 *
 * App Check can't cover this one, RevenueCat's servers have no app to
 * attest with, so the shared secret is the whole door. Anything without it
 * gets a 401 and is never looked at.
 */
export const revenueCatWebhook = onRequest(
  {
    // RevenueCat's servers carry no Google identity, so Cloud Run must let
    // anyone knock. The shared secret above is the door; without this the
    // platform answered 403 before the function ever ran.
    invoker: "public",
    secrets: [revenueCatSecretKey, revenueCatWebhookSecret],
    cpu: 1,
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method not allowed");
      return;
    }

    const expected = revenueCatWebhookSecret.value();
    if (!expected) {
      logger.error("REVENUECAT_WEBHOOK_SECRET is not set; webhook is refusing everything.");
      response.status(500).send("Not configured");
      return;
    }

    const offered = request.get("Authorization") ?? "";
    // Constant-time so the header can't be guessed a byte at a time.
    const a = Buffer.from(offered);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      logger.warn("Rejected a webhook with a bad Authorization header.");
      response.status(401).send("Unauthorized");
      return;
    }

    try {
      const touched = await applyWebhookEvent(request.body?.event, revenueCatSecretKey.value());
      logger.info("Webhook applied", { type: request.body?.event?.type, ids: touched });
    } catch (error) {
      // A 5xx makes RevenueCat retry, which is what we want for a
      // transient Firestore hiccup.
      logger.error("Webhook failed", { error: String(error) });
      response.status(500).send("Retry");
      return;
    }
    response.status(200).send("OK");
  }
);

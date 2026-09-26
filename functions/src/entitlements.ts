/**
 * Who is allowed to spend Azure tokens, and who has already had their one
 * free go.
 *
 * Two questions, answered here and nowhere else:
 *
 *   1. Is this person subscribed? RevenueCat is the source of truth. Its
 *      webhook mirrors entitlement state into Firestore so the hot path is
 *      one document read; the REST API is the fallback whenever the mirror
 *      is missing or stale (a purchase whose webhook hasn't landed yet, a
 *      restore on a new phone).
 *
 *   2. Have they already spent the free loop? The ledger lives in Firestore
 *      keyed by the app user id, which the app keeps in the Keychain. The
 *      Keychain outlives an app delete, so a reinstall lands on the same
 *      ledger row and gains nothing. The client never gets a say: it sends
 *      an id, and the answer is computed here.
 *
 * The client cannot lie its way past either question. It can only ask.
 */

import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

if (getApps().length === 0) initializeApp();
/** The project's Firestore database is the named one, "satisfed", not
 *  "(default)". Left unnamed, the Admin SDK answers every read with
 *  "5 NOT_FOUND" and the webhook and the gate both fail. */
export const FIRESTORE_DATABASE = "satisfed";
const db = getFirestore(FIRESTORE_DATABASE);

/** The entitlement configured in the RevenueCat dashboard. */
export const ENTITLEMENT_ID = "Premium";

const COLLECTION = "subscribers";
const REVENUECAT_API = "https://api.revenuecat.com/v1";

/** One loop is a craving carried through to its summary. These are the
 *  ceilings on what "one loop" can cost if someone tries to stretch it:
 *  generous for an honest run, cheap for a dishonest one. */
const FREE_MAX_CALLS = 10;
const FREE_MAX_VISION = 3;
/** A loop left open is a loop abandoned. Long enough to put the phone down
 *  and come back, short enough that it can't be parked open for a week. */
const FREE_WINDOW_MS = 45 * 60 * 1000;

/** How long a "not subscribed" mirror is trusted before we ask RevenueCat
 *  again. A "subscribed" mirror is trusted until its own expiry instead. */
const MIRROR_MAX_AGE_MS = 6 * 60 * 60 * 1000;
/** Before refusing anyone, RevenueCat is asked directly once, in case the
 *  "not subscribed" mirror is a purchase whose webhook hasn't landed. This
 *  is how often that live re-check may repeat for one id, so a client
 *  looping on a refused call can't turn the gate into a RevenueCat relay. */
const RECHECK_MIN_INTERVAL_MS = 30 * 1000;

export type ProState = "pro" | "free" | "unknown";
export type FreeLoopStatus = "unused" | "active" | "used";
/** The AI features, as the ledger sees them. The free go belongs to
 *  whichever one opens it: the plate flow is several calls (a photo read,
 *  a deck, a summary) and stays open until its summary; the other two are
 *  one call each and close on their first answer. A second feature asked
 *  for while the first is still open meets the paywall. */
export type Feature = "plates" | "ideas" | "cravings";

/** Thrown at the app when the free loop is spent. The app matches on the
 *  code, not the message, and answers by showing the paywall. */
export const PAYWALL_CODE = "PAYWALL_REQUIRED";

// MARK: - Identity

/** The app sends the UUID it keeps in the Keychain. Shape-check it so a
 *  malformed id can't be used to fan out ledger rows or to smuggle a path
 *  segment into a document reference. */
export function appUserID(value: unknown): string {
  if (typeof value !== "string") throw new HttpsError("invalid-argument", "Missing app user id.");
  const trimmed = value.trim();
  if (!/^[A-Za-z0-9._:-]{8,128}$/.test(trimmed)) {
    throw new HttpsError("invalid-argument", "Malformed app user id.");
  }
  return trimmed;
}

// MARK: - RevenueCat

interface RevenueCatEntitlement {
  expires_date?: string | null;
  product_identifier?: string;
}

/** Asks RevenueCat directly. Returns `unknown` for anything that isn't a
 *  clear answer (no key configured, network trouble, a 5xx) so the caller
 *  can fail open rather than lock out someone who has actually paid. */
interface Lookup {
  state: ProState;
  /** When the grant runs out. Null means lifetime, or nothing to expire. */
  expiresAtMS: number | null;
}

const INCONCLUSIVE: Lookup = { state: "unknown", expiresAtMS: null };

/** RevenueCat keeps sandbox and production purchases apart, and its REST
 *  API answers from the production side unless told otherwise. The SDK
 *  tags its own requests, which is why a simulator or TestFlight purchase
 *  unlocks the app while a plain lookup sees nothing. So: production
 *  first, and only when that is a definite "free", the sandbox view. A
 *  real App Store purchase is answered by the first call. */
async function lookupRevenueCat(id: string, secretKey: string | undefined): Promise<Lookup> {
  const production = await fetchSubscriber(id, secretKey, false);
  if (production.state !== "free") return production;
  const sandbox = await fetchSubscriber(id, secretKey, true);
  if (sandbox.state === "pro") {
    logger.info("RevenueCat granted this id from a sandbox purchase", { id });
    return sandbox;
  }
  // The production answer was a definite no; a sandbox error doesn't
  // make it any less definite.
  return production;
}

async function fetchSubscriber(id: string, secretKey: string | undefined, sandbox: boolean): Promise<Lookup> {
  if (!secretKey) {
    // A configuration hole, not a network blip: without the key every
    // never-seen id passes the gate. Loud on purpose.
    logger.error("REVENUECAT_SECRET_KEY is not set; entitlements can't be checked and the gate is failing open.");
    return INCONCLUSIVE;
  }
  const headers: Record<string, string> = { Authorization: `Bearer ${secretKey}`, Accept: "application/json" };
  if (sandbox) headers["X-Is-Sandbox"] = "true";
  let response: Response;
  try {
    response = await fetch(`${REVENUECAT_API}/subscribers/${encodeURIComponent(id)}`, { headers });
  } catch (error) {
    logger.warn("RevenueCat lookup failed", { id, sandbox, error: String(error) });
    return INCONCLUSIVE;
  }

  // 404 is a definite answer: RevenueCat has never heard of this id, so
  // there is nothing to grant. Every other failure is inconclusive.
  if (response.status === 404) {
    logger.info("RevenueCat has never seen this id", { id, sandbox });
    return { state: "free", expiresAtMS: null };
  }
  if (!response.ok) {
    logger.warn("RevenueCat lookup returned an error", { id, sandbox, status: response.status });
    return INCONCLUSIVE;
  }

  try {
    const body = (await response.json()) as {
      subscriber?: { entitlements?: Record<string, RevenueCatEntitlement> };
    };
    const entitlements = body?.subscriber?.entitlements ?? {};
    const entitlement = entitlements[ENTITLEMENT_ID];
    if (!entitlement) {
      // Which entitlements it does carry is the one fact that tells a
      // never-subscribed id apart from a product that isn't attached to
      // ours, or a key that belongs to another project.
      logger.info("RevenueCat lookup found no entitlement", { id, sandbox, entitlements: Object.keys(entitlements) });
      return { state: "free", expiresAtMS: null };
    }
    // A null expiry is a lifetime grant.
    if (!entitlement.expires_date) return { state: "pro", expiresAtMS: null };
    const expiresAtMS = Date.parse(entitlement.expires_date);
    const state: ProState = expiresAtMS > Date.now() ? "pro" : "free";
    if (state === "free") logger.info("RevenueCat entitlement has lapsed", { id, sandbox, expiresAt: entitlement.expires_date });
    return { state, expiresAtMS };
  } catch (error) {
    logger.warn("RevenueCat lookup was unreadable", { id, sandbox, error: String(error) });
    return INCONCLUSIVE;
  }
}

/** Writes what RevenueCat said into the mirror, so the next call is a
 *  single document read instead of a round trip. */
async function writeMirror(id: string, state: ProState, expiresAtMS: number | null): Promise<void> {
  if (state === "unknown") return;
  await db.collection(COLLECTION).doc(id).set(
    {
      entitlement: {
        active: state === "pro",
        expiresAtMS,
        checkedAtMS: Date.now(),
      },
    },
    { merge: true }
  );
}

/** Re-reads one subscriber from RevenueCat and updates the mirror. The
 *  webhook calls this rather than trying to interpret fifteen event types:
 *  whatever happened, the answer is whatever RevenueCat says now. */
export async function refreshFromRevenueCat(id: string, secretKey: string | undefined): Promise<ProState> {
  const { state, expiresAtMS } = await lookupRevenueCat(id, secretKey);
  if (state !== "unknown") await writeMirror(id, state, expiresAtMS);
  return state;
}

// MARK: - Is this person subscribed?

interface Mirror {
  active?: boolean;
  expiresAtMS?: number | null;
  checkedAtMS?: number;
}

function mirrorVerdict(mirror: Mirror | undefined): ProState | null {
  if (!mirror) return null;
  const now = Date.now();
  if (mirror.active === true) {
    // Trusted until the subscription's own expiry. A cancellation arrives
    // as a webhook long before that, so this doesn't hand out free months.
    if (mirror.expiresAtMS == null || mirror.expiresAtMS > now) return "pro";
    return null; // Lapsed by the clock: re-check rather than assume.
  }
  if (mirror.active === false && typeof mirror.checkedAtMS === "number") {
    return now - mirror.checkedAtMS < MIRROR_MAX_AGE_MS ? "free" : null;
  }
  return null;
}

// MARK: - The free loop ledger

interface Ledger {
  status?: FreeLoopStatus;
  /** Which feature the free go was spent on. */
  feature?: Feature;
  startedAtMS?: number;
  calls?: number;
  visionCalls?: number;
}

/** What the ledger transaction decided about one call. */
type Outcome = "blocked" | "allowed";

export interface GateResult {
  pro: ProState;
  freeLoop: FreeLoopStatus;
}

/** Reads entitlement and free-loop state without spending anything. Backs
 *  the `entitlementStatus` callable, which is what lets the app show the
 *  paywall at the right moment instead of guessing. */
export async function readState(id: string, secretKey: string | undefined, fresh = false): Promise<GateResult> {
  const snapshot = await db.collection(COLLECTION).doc(id).get();
  const data = snapshot.data() ?? {};
  const ledger = (data.freeLoop ?? {}) as Ledger;

  const settled = mirrorVerdict(data.entitlement as Mirror | undefined);
  let pro = settled;
  // Right after a purchase the mirror can still say "free" for hours; the
  // app knows better and says so. A "pro" mirror is never second-guessed.
  if (pro === "free" && fresh) pro = null;
  if (pro === null) {
    const lookup = await lookupRevenueCat(id, secretKey);
    if (lookup.state !== "unknown") {
      pro = lookup.state;
      await writeMirror(id, pro, lookup.expiresAtMS);
    } else {
      // An inconclusive re-check leaves a valid mirror's word standing, so
      // a client repeating `fresh` can't turn RevenueCat trouble into
      // "unknown" and a free pass.
      pro = settled ?? "unknown";
    }
  }

  return { pro, freeLoop: ledger.status ?? "unused" };
}

/**
 * The gate on every AI call.
 *
 * Subscribers pass straight through and their free loop is left untouched,
 * so a cancellation later still leaves them the one free run they never
 * spent. Everyone else runs on the ledger: the first call opens the loop
 * and names the feature it went on, that feature's payoff closes it (the
 * plate summary, or the one answer from the recipe maker or the craving
 * translator), and the caps close it early if someone leans on it. Once
 * it is closed, the answer is the paywall, for every feature. While it is
 * open, any other feature is the paywall too: one free go means one, not
 * one per feature.
 *
 * Deliberately fails open when entitlement can't be determined. Charging
 * someone and then refusing to answer them is the one outcome worth
 * spending a few tokens to avoid.
 */
export async function authorize(
  id: string,
  options: { feature: Feature; isVision: boolean; enforce: boolean; secretKey: string | undefined; fresh?: boolean }
): Promise<GateResult> {
  const reference = db.collection(COLLECTION).doc(id);
  const snapshot = await reference.get();
  const data = snapshot.data() ?? {};
  const mirror = data.entitlement as Mirror | undefined;

  const settled = mirrorVerdict(mirror);
  let pro = settled;
  if (pro === "free" && options.fresh) pro = null;
  // Whether "free" came from RevenueCat just now, or from a mirror that
  // may predate a purchase. Only the latter is worth a second look before
  // anyone is refused.
  let verifiedLive = false;
  if (pro === null) {
    const lookup = await lookupRevenueCat(id, options.secretKey);
    verifiedLive = true;
    if (lookup.state !== "unknown") {
      pro = lookup.state;
      await writeMirror(id, pro, lookup.expiresAtMS);
    } else {
      // Same rule as `readState`: a valid mirror outranks an inconclusive
      // re-check the client asked for. Only a mirror that has really
      // lapsed leaves "unknown", which is the fail-open case.
      pro = settled ?? "unknown";
    }
  }

  // Subscribed, or we couldn't find out. Either way, answer them, and
  // leave the ledger alone so a free loop never quietly burns down while
  // someone is paying for it.
  if (pro !== "free") {
    return { pro, freeLoop: ((data.freeLoop ?? {}) as Ledger).status ?? "unused" };
  }

  const outcome = await db.runTransaction(async (transaction): Promise<Outcome> => {
    const fresh = await transaction.get(reference);
    const ledger = ((fresh.data() ?? {}).freeLoop ?? {}) as Ledger;
    const now = Date.now();
    const state = ledger.status ?? "unused";

    if (state === "used") return "blocked";

    const active = state === "active";
    // The free go is already on another feature. Asking for a second one
    // is walking away from the first, so the go is spent here and now:
    // one free go means one, finished or not. Marking it used (rather
    // than leaving it open) is what lets the app show the paywall up
    // front next time, and keeps "your free round is done" true.
    if (active && ledger.feature && ledger.feature !== options.feature) {
      transaction.set(reference, { freeLoop: { status: "used", closedAtMS: now } }, { merge: true });
      return "blocked";
    }
    const started = active ? ledger.startedAtMS ?? now : now;
    const calls = (active ? ledger.calls ?? 0 : 0) + 1;
    const visionCalls = (active ? ledger.visionCalls ?? 0 : 0) + (options.isVision ? 1 : 0);

    const expired = now - started > FREE_WINDOW_MS;
    const overCap = calls > FREE_MAX_CALLS || visionCalls > FREE_MAX_VISION;

    // Closed early only when they leaned on it. The summary, the loop's
    // natural end, closes it through `closeFreeLoop` once it has actually
    // been produced, so a failed summary never leaves a spent loop behind.
    const closing = expired || overCap;
    transaction.set(
      reference,
      {
        freeLoop: {
          status: closing ? "used" : "active",
          feature: options.feature,
          startedAtMS: started,
          calls,
          visionCalls,
          ...(closing ? { closedAtMS: now } : {}),
        },
      },
      { merge: true }
    );

    return closing ? "blocked" : "allowed";
  });

  if (outcome === "blocked") {
    // The mirror said "free", but a purchase can be minutes old and its
    // webhook still in flight. Ask RevenueCat directly before turning
    // anyone away; a definite "pro" wins, anything less leaves the mirror's
    // verdict standing.
    const lastChecked = mirror?.checkedAtMS ?? 0;
    if (!verifiedLive && Date.now() - lastChecked > RECHECK_MIN_INTERVAL_MS) {
      const lookup = await lookupRevenueCat(id, options.secretKey);
      if (lookup.state !== "unknown") await writeMirror(id, lookup.state, lookup.expiresAtMS);
      if (lookup.state === "pro") return { pro: "pro", freeLoop: "used" };
    }
    // The refusal is a plain 403 to the platform, so it is spelled out
    // here: what the mirror said, whether RevenueCat was asked, and
    // whether the app claimed a fresh purchase.
    logger.warn("Paywall refused this call", {
      id,
      feature: options.feature,
      mirror: settled ?? "none",
      askedRevenueCat: verifiedLive,
      fresh: options.fresh === true,
      enforce: options.enforce,
    });
    if (!options.enforce) return { pro: "free", freeLoop: "used" };
    throw new HttpsError("permission-denied", PAYWALL_CODE, { code: PAYWALL_CODE, reason: "free_loop_used" });
  }

  return { pro: "free", freeLoop: "active" };
}

/**
 * Marks the free loop spent. Called once a feature's payoff has actually
 * been produced (the plate summary, the recipe maker's ideas, the craving
 * read), which is the loop's natural end. A loop that was never opened (a
 * subscriber's, say) is left alone: closing it would spend a free run they
 * never had.
 */
export async function closeFreeLoop(id: string): Promise<void> {
  const reference = db.collection(COLLECTION).doc(id);
  await db.runTransaction(async (transaction) => {
    const fresh = await transaction.get(reference);
    const ledger = ((fresh.data() ?? {}).freeLoop ?? {}) as Ledger;
    if (ledger.status !== "active") return;
    transaction.set(reference, { freeLoop: { status: "used", closedAtMS: Date.now() } }, { merge: true });
  });
}

// MARK: - Webhook

interface WebhookEvent {
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  entitlement_ids?: string[] | null;
  entitlement_id?: string | null;
  expiration_at_ms?: number | null;
  transferred_from?: string[];
  transferred_to?: string[];
}

/** Types that end access the moment they arrive. A cancellation is not one
 *  of them: someone who cancels keeps what they paid for until it runs out,
 *  and RevenueCat sends EXPIRATION when it actually does. */
const REVOKING_EVENTS = new Set(["EXPIRATION", "SUBSCRIPTION_PAUSED"]);

/** Types that can mean access was just granted. Anything else that arrives
 *  without an expiry (TEST, BILLING_ISSUE, SUBSCRIBER_ALIAS, ...) says
 *  nothing about access and must not be read as a grant. */
const GRANTING_EVENTS = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "NON_RENEWING_PURCHASE",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
]);

/** What the event itself implies, used only when RevenueCat's API can't be
 *  reached (no secret key configured, or it was down). Less authoritative
 *  than a lookup, but far better than leaving a fresh subscriber with an
 *  empty mirror. */
function verdictFromEvent(event: WebhookEvent): ProState | null {
  const ids = event.entitlement_ids ?? (event.entitlement_id ? [event.entitlement_id] : null);
  // An event that names entitlements but not ours says nothing about ours.
  if (ids && !ids.includes(ENTITLEMENT_ID)) return null;
  if (event.type && REVOKING_EVENTS.has(event.type)) return "free";
  const expiry = event.expiration_at_ms;
  if (expiry == null) return event.type && GRANTING_EVENTS.has(event.type) ? "pro" : null;
  return expiry > Date.now() ? "pro" : "free";
}

/** Every id one event touches. Aliases matter: the same person can reach
 *  RevenueCat under more than one id, and all of them must agree. */
function affectedIDs(event: WebhookEvent): string[] {
  const raw = [
    event.app_user_id,
    event.original_app_user_id,
    ...(event.aliases ?? []),
    ...(event.transferred_from ?? []),
    ...(event.transferred_to ?? []),
  ];
  const seen = new Set<string>();
  for (const value of raw) {
    if (typeof value !== "string") continue;
    const trimmed = value.trim();
    // Same shape rule as the callable path, so a webhook can't create a
    // ledger row the app could never address.
    if (/^[A-Za-z0-9._:-]{8,128}$/.test(trimmed)) seen.add(trimmed);
  }
  return [...seen];
}

/** Brings the mirror back in line with RevenueCat for every id an event
 *  touches. Asking RevenueCat what is true now beats interpreting fifteen
 *  event types, so that is the first thing tried for each id. */
export async function applyWebhookEvent(event: unknown, secretKey: string | undefined): Promise<number> {
  if (!event || typeof event !== "object") return 0;
  const typed = event as WebhookEvent;
  const ids = affectedIDs(typed);
  const fallback = verdictFromEvent(typed);

  await Promise.all(
    ids.map(async (id) => {
      const state = await refreshFromRevenueCat(id, secretKey);
      if (state === "unknown" && fallback !== null) {
        await writeMirror(id, fallback, typed.expiration_at_ms ?? null);
      }
    })
  );
  return ids.length;
}

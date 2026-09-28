/**
 * How fast, and how much, the AI can be asked for.
 *
 * The paywall gate decides who may use the AI at all; this decides how
 * hard. App Check proves a call came from a genuine copy of the app, but
 * the id inside it is only what that copy says it is, so a fresh id is a
 * fresh free loop. The per-id limits keep any one id to a human pace; the
 * daily budgets put a ceiling on the Azure bill however many ids turn up.
 *
 * Fixed windows, one Firestore document per key per window. Each carries
 * an `expiresAt` for a TTL policy on the `rateLimits` collection to sweep
 * up; nothing reads a window once it has passed.
 */

import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { db } from "./entitlements";

const COLLECTION = "rateLimits";

export const MINUTE_MS = 60 * 1000;
export const HOUR_MS = 60 * MINUTE_MS;
export const DAY_MS = 24 * HOUR_MS;

/**
 * Counts one call against `key` in the current window. True when it fits
 * under `limit`, false when the window is already full; a refused call is
 * not counted, so a burst that was turned away doesn't keep the window
 * shut for longer.
 *
 * Fails open: if Firestore can't answer, the call goes through and the
 * failure is logged. The limiter is a guard on the bill, not a reason for
 * the app to stop working.
 */
export async function hit(key: string, limit: number, windowMs: number): Promise<boolean> {
  const windowStart = Math.floor(Date.now() / windowMs) * windowMs;
  // Ids are shape-checked upstream, but a "/" would make this a path.
  const reference = db.collection(COLLECTION).doc(`${key}:${windowStart}`.replace(/\//g, "_"));
  try {
    return await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const count = (snapshot.get("count") as number | undefined) ?? 0;
      if (count >= limit) return false;
      transaction.set(reference, {
        count: count + 1,
        expiresAt: Timestamp.fromMillis(windowStart + windowMs + DAY_MS),
      });
      return true;
    });
  } catch (error) {
    logger.error("Rate limiter couldn't be read; letting the call through", { key, error: String(error) });
    return true;
  }
}

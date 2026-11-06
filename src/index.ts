// Client version protocol (SPEC.md): parse `X-Client-Version`, evaluate it against a policy, and
// produce the response headers / 426 refusal. Framework-neutral; no dependencies.

export const HEADER = "X-Client-Version";
export const QUERY_PARAM = "client_version";
export const UPGRADE_HEADER = "X-Client-Upgrade";
export const UPGRADE_URL_HEADER = "X-Upgrade-URL";
export const UPGRADE_REQUIRED_MESSAGE = "This version of the app is no longer supported. Please update.";

export interface ClientVersion {
  app: string;
  version: string;
  build: string | null;
  platform: string;
}

export interface PolicyEntry {
  app: string;
  platform: string;
  /** Oldest version still allowed to write. */
  minimum?: string | null;
  /** Oldest version that is not nudged. */
  recommended?: string | null;
  upgradeUrl?: string | null;
}

export type UpgradeLevel = "none" | "recommended" | "required";

export interface Evaluation {
  level: UpgradeLevel;
  /** True when the request must be answered with `426` instead of being served. */
  refuse: boolean;
  /** Headers to add to the response (also to the 426). */
  headers: Record<string, string>;
  /** The 426 body when `refuse`. */
  body?: { error: "upgrade_required"; message: string; upgradeUrl?: string };
  client: ClientVersion | null;
}

const PATTERN = /^([a-z][a-z0-9-]*)\/(\d+(?:\.\d+){0,3})(?:\+([0-9A-Za-z.-]+))?\s+\(([a-z][a-z0-9-]*)\)$/;
const VERSION = /^\d+(?:\.\d+){0,3}$/;
const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

/** Parses `X-Client-Version`; `null` when missing or malformed (an unknown client). */
export function parse(value: string | null | undefined): ClientVersion | null {
  if (value == null) return null;
  const m = PATTERN.exec(value.trim());
  if (!m) return null;
  return { app: m[1]!, version: m[2]!, build: m[3] ?? null, platform: m[4]! };
}

/** Numeric, component-wise comparison; missing components are 0. Returns -1, 0 or 1. */
export function compare(a: string, b: string): -1 | 0 | 1 {
  if (!VERSION.test(a) || !VERSION.test(b)) throw new Error(`not a version: ${VERSION.test(a) ? b : a}`);
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] ?? 0;
    const y = pb[i] ?? 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

/** True when the client is at least `version`; an unknown client counts as current (true). */
export function atLeast(client: ClientVersion | null, version: string): boolean {
  return client === null || compare(client.version, version) >= 0;
}

function findEntry(policy: readonly PolicyEntry[], client: ClientVersion): PolicyEntry | undefined {
  return policy.find((e) => e.app === client.app && e.platform === client.platform);
}

/** The upgrade level for a client under a policy. */
export function levelFor(policy: readonly PolicyEntry[], client: ClientVersion | null): { level: UpgradeLevel; entry?: PolicyEntry } {
  if (!client) return { level: "none" };
  const entry = findEntry(policy, client);
  if (!entry) return { level: "none" };
  if (entry.minimum && compare(client.version, entry.minimum) < 0) return { level: "required", entry };
  if (entry.recommended && compare(client.version, entry.recommended) < 0) return { level: "recommended", entry };
  return { level: "none", entry };
}

/**
 * Evaluates a request: `clientVersion` is the `X-Client-Version` header (or the `client_version`
 * query parameter), `method` the HTTP method (a WebSocket upgrade is a `GET`).
 */
export function evaluate(policy: readonly PolicyEntry[], clientVersion: string | null | undefined, method: string): Evaluation {
  const client = parse(clientVersion);
  const { level, entry } = levelFor(policy, client);
  const headers: Record<string, string> = {};
  if (level === "none") return { level, refuse: false, headers, client };

  headers[UPGRADE_HEADER] = level;
  if (entry?.upgradeUrl) headers[UPGRADE_URL_HEADER] = entry.upgradeUrl;
  const refuse = level === "required" && !SAFE_METHODS.has(method.toUpperCase());
  if (!refuse) return { level, refuse, headers, client };

  const body: NonNullable<Evaluation["body"]> = { error: "upgrade_required", message: UPGRADE_REQUIRED_MESSAGE };
  if (entry?.upgradeUrl) body.upgradeUrl = entry.upgradeUrl;
  return { level, refuse, headers, body, client };
}

/** The header value if present, else the query parameter (browser WebSockets cannot set headers). */
export function clientVersionOf(request: Request): string | null {
  return request.headers.get(HEADER) ?? new URL(request.url).searchParams.get(QUERY_PARAM);
}

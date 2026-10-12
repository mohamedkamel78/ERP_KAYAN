import { networkInterfaces } from 'node:os';

/**
 * How the program behaves when it is not the only thing between the browser
 * and the machine the program runs on.
 *
 * Two deployments matter, and they are the same two the office keeps asking
 * for:
 *
 *   1. the phones and tablets on the company's own network opening
 *      `http://192.168.1.20:3000` — the program answers on every interface by
 *      default, so this needs nothing but a firewall that lets the port
 *      through;
 *   2. someone outside the building, which has to go through a TLS-terminating
 *      proxy (Caddy, nginx) because a program that ships with a password file
 *   * and a database on one machine is not a program that should hold its own
 *      certificate.
 *
 * The second one is where a server quietly tells lies: every request arrives
 * from the proxy, so the caller's address, the protocol and the host are all
 * the proxy's unless the headers the proxy forwards are believed. Believing
 * them from anybody is worse than not believing them at all — anyone could
 * invent an address and reset their own rate-limit counter. So the belief is
 * one switch (`TRUST_PROXY`), and everything that depends on it — the
 * rate limiter's key, the `https`-only headers, the redirect — reads the
 * answer from here rather than guessing.
 */

/// The variable that says a proxy stands in front of this server, and how far
/// to believe it.
export const TRUST_PROXY_VARIABLE = 'TRUST_PROXY';

/// The variable that makes plain HTTP answers with a redirect to HTTPS.
export const REQUIRE_HTTPS_VARIABLE = 'KAYAN_REQUIRE_HTTPS';

/// The variable that switches the HSTS header off for a deployment that has
/// no hope of serving HTTPS on every port it answers on.
export const HSTS_VARIABLE = 'KAYAN_HSTS';

/// The variable that sets how long a browser should keep using HTTPS here.
export const HSTS_MAX_AGE_VARIABLE = 'KAYAN_HSTS_MAX_AGE';

/// One year, which is what an operator who has not thought about it wants:
/// short enough that a mistake is recoverable, long enough to be worth sending.
export const DEFAULT_HSTS_MAX_AGE_SECONDS = 31_536_000;

/**
 * How much to believe `X-Forwarded-*`.
 *
 * `true` believes the chain from any address — right when the proxy is the
 * only thing that can reach the server (a container network, a firewalled
 * machine). `loopback` believes only a proxy standing on this same machine,
 * which is what a Caddy or nginx installed next to the program is. A number
 * counts the proxies in front — `1` for one, `2` for a load balancer in front
 * of a proxy.
 *
 * A value that means none of those is read as "not trusted", and said out
 * loud by {@link proxyTrustWarning}: a typo in a security switch should not
 * quietly become the least safe setting.
 */
export type ProxyTrust = false | true | 'loopback' | number;

export function proxyTrust(raw: string | undefined = process.env[TRUST_PROXY_VARIABLE]): ProxyTrust {
  const value = (raw ?? '').trim().toLowerCase();
  if (value === '' || value === 'false' || value === '0' || value === 'off' || value === 'no') {
    return false;
  }
  if (value === 'true' || value === '1' || value === 'on' || value === 'yes') return true;
  if (value === 'loopback' || value === 'local') return 'loopback';
  const hops = Number(value);
  if (Number.isInteger(hops) && hops > 1) return hops;
  return false;
}

/// The sentence to log when the switch was set to something that means nothing.
export function proxyTrustWarning(
  raw: string | undefined = process.env[TRUST_PROXY_VARIABLE],
): string | null {
  const value = (raw ?? '').trim();
  if (value === '') return null;
  if (proxyTrust(value) !== false) return null;
  return (
    `${TRUST_PROXY_VARIABLE}="${value}" means nothing to this program, so ` +
    'X-Forwarded-* headers are not believed. Use true (any address), ' +
    'loopback (a proxy on this machine), or the number of proxies in front.'
  );
}

/// `true` when the deployment insists on HTTPS; anything else keeps plain HTTP working.
export function httpsRedirectRequired(
  raw: string | undefined = process.env[REQUIRE_HTTPS_VARIABLE],
): boolean {
  const value = (raw ?? '').trim().toLowerCase();
  return value === 'true' || value === '1' || value === 'on' || value === 'yes';
}

/**
 * Where a request should be sent instead, or null when it should be answered.
 *
 * The health route is never redirected: a proxy that checks whether this
 * server is alive does so over plain HTTP on the loopback interface, and a
 * redirect it cannot follow would read as a dead server on a healthy one.
 */
export function httpsRedirectTarget(options: {
  required: boolean;
  secure: boolean;
  host?: string | string[];
  url?: string;
}): string | null {
  if (!options.required || options.secure) return null;
  const host = Array.isArray(options.host) ? options.host[0] : options.host;
  if (!host) return null;
  const url = options.url ?? '/';
  if (url.startsWith('/api/v1/health') || url === '/health') return null;
  return `https://${host}${url.startsWith('/') ? url : `/${url}`}`;
}

/**
 * The headers a browser needs to hear, whatever the answer is about.
 *
 * `nosniff` because a file the program hands out is what it says it is;
 * `no-referrer` because an address in this program contains a download ticket
 * and a ticket is worth exactly one minute of one file, which is not
 * something a third-party link should be handed; `DENY` because a page that
 * holds a company's ledger inside someone else's frame is a click on
 * somebody else's page.
 *
 * HSTS only over TLS, and only when the operator has not switched it off —
 * sent over plain HTTP it would be remembered against the port-less host and
 * could lock a whole office out of a LAN address that has no certificate.
 */
export function clientSecurityHeaders(options: {
  secure: boolean;
  hsts: boolean;
  hstsMaxAgeSeconds?: number;
}): Record<string, string> {
  const headers: Record<string, string> = {
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'X-Frame-Options': 'DENY',
  };
  if (options.secure && options.hsts) {
    const maxAge =
      options.hstsMaxAgeSeconds ?? DEFAULT_HSTS_MAX_AGE_SECONDS;
    headers['Strict-Transport-Security'] =
      `max-age=${maxAge}; includeSubDomains`;
  }
  return headers;
}

/// Whether HSTS should be sent at all.
export function hstsEnabled(
  raw: string | undefined = process.env[HSTS_VARIABLE],
): boolean {
  const value = (raw ?? '').trim().toLowerCase();
  return !(value === 'false' || value === '0' || value === 'off' || value === 'no');
}

/// How long a browser should keep coming back over HTTPS, in seconds.
export function hstsMaxAgeSeconds(
  raw: string | undefined = process.env[HSTS_MAX_AGE_VARIABLE],
): number {
  const value = (raw ?? '').trim();
  // An empty variable is a variable that was never set: `Number('')` is 0,
  // and 0 means "forget HTTPS tomorrow", which is not what an unset value says.
  if (value === '') return DEFAULT_HSTS_MAX_AGE_SECONDS;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_HSTS_MAX_AGE_SECONDS;
  return Math.floor(parsed);
}

/// The machine's own LAN addresses: IPv4, not the loopback, not internal.
export function lanAddresses(
  interfaces: ReturnType<typeof networkInterfaces> = networkInterfaces(),
): string[] {
  const found: string[] = [];
  for (const name of Object.keys(interfaces)) {
    for (const entry of interfaces[name] ?? []) {
      if (entry.family !== 'IPv4' || entry.internal) continue;
      if (!found.includes(entry.address)) found.push(entry.address);
    }
  }
  return found;
}

/**
 * What to print when the server has started.
 *
 * The addresses a person can actually type, and only those. `0.0.0.0` is not
 * one of them — it is the answer to "which interfaces", and printing it is how
 * somebody ends up typing it. The LAN lines are what makes "open it on the
 * tablet" a thing a person can do without being told a number by a programmer.
 */
export function describeAccess(options: {
  port: number;
  host: string;
  lan?: string[];
  proxy: ProxyTrust;
  requireHttps: boolean;
}): string[] {
  const lines = [
    `Local web access: http://localhost:${options.port}`,
    `API on this machine: http://127.0.0.1:${options.port}/api/v1`,
  ];
  if (options.host === '0.0.0.0') {
    for (const address of options.lan ?? []) {
      lines.push(`LAN access (any device on this network): http://${address}:${options.port}`);
    }
    lines.push(
      'LAN access is open on this port: the Windows firewall must allow it, ' +
        'and only people you trust can sign in. See docs/NETWORK_ACCESS.md.',
    );
  } else {
    lines.push(
      `Bound to ${options.host}: only this machine can reach the program.`,
    );
  }
  if (options.proxy === false) {
    lines.push(
      `No proxy trusted: if a TLS proxy stands in front of this server, set ` +
        `${TRUST_PROXY_VARIABLE}=loopback (same machine) or true (another machine), ` +
        `or every user looks like the proxy to the rate limiter and to HTTPS.`,
    );
  }
  if (options.requireHttps && options.proxy === false) {
    lines.push(
      `${REQUIRE_HTTPS_VARIABLE} is on while no proxy is trusted: plain HTTP ` +
        'requests are redirected to a port this server may not be listening on.',
    );
  }
  return lines;
}

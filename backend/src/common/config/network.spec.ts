import {
  DEFAULT_HSTS_MAX_AGE_SECONDS,
  clientSecurityHeaders,
  describeAccess,
  hstsEnabled,
  hstsMaxAgeSeconds,
  httpsRedirectRequired,
  httpsRedirectTarget,
  lanAddresses,
  proxyTrust,
  proxyTrustWarning,
} from './network';

describe('believing a proxy', () => {
  it('trusts nothing when the switch is unset', () => {
    expect(proxyTrust('')).toBe(false);
    expect(proxyTrust(undefined)).toBe(false);
    expect(proxyTrust('false')).toBe(false);
  });

  it('trusts the whole chain, the loopback, or a number of hops', () => {
    expect(proxyTrust('true')).toBe(true);
    expect(proxyTrust(' TRUE ')).toBe(true);
    expect(proxyTrust('loopback')).toBe('loopback');
    expect(proxyTrust('2')).toBe(2);
  });

  it('reads an unusable value as "not trusted" and says so', () => {
    // The safe answer and the honest one: a typo in a security switch must not
    // become the least safe setting, and must not pass for a working one.
    expect(proxyTrust('yes please')).toBe(false);
    expect(proxyTrustWarning('yes please')).toContain('means nothing');
    expect(proxyTrustWarning('true')).toBeNull();
    expect(proxyTrustWarning(undefined)).toBeNull();
  });
});

describe('the headers a browser is answered with', () => {
  it('never sends HSTS over plain HTTP', () => {
    const headers = clientSecurityHeaders({ secure: false, hsts: true });
    expect(headers['Strict-Transport-Security']).toBeUndefined();
    expect(headers['X-Content-Type-Options']).toBe('nosniff');
    expect(headers['X-Frame-Options']).toBe('DENY');
    // A download address carries a ticket; it must not be handed to whoever
    // the page links to.
    expect(headers['Referrer-Policy']).toBe('no-referrer');
  });

  it('sends HSTS over TLS, with the length the operator chose', () => {
    expect(
      clientSecurityHeaders({ secure: true, hsts: true })[
        'Strict-Transport-Security'
      ],
    ).toBe(`max-age=${DEFAULT_HSTS_MAX_AGE_SECONDS}; includeSubDomains`);
    expect(
      clientSecurityHeaders({ secure: true, hsts: false })[
        'Strict-Transport-Security'
      ],
    ).toBeUndefined();
  });

  it('lets an installation with no certificate switch HSTS off', () => {
    expect(hstsEnabled(undefined)).toBe(true);
    expect(hstsEnabled('false')).toBe(false);
    expect(hstsMaxAgeSeconds('')).toBe(DEFAULT_HSTS_MAX_AGE_SECONDS);
    expect(hstsMaxAgeSeconds('600')).toBe(600);
    // A negative or nonsense value is not a licence to send a nonsense header.
    expect(hstsMaxAgeSeconds('-5')).toBe(DEFAULT_HSTS_MAX_AGE_SECONDS);
    expect(hstsMaxAgeSeconds('soon')).toBe(DEFAULT_HSTS_MAX_AGE_SECONDS);
  });
});

describe('sending people to HTTPS', () => {
  it('stays quiet unless the deployment asks', () => {
    expect(httpsRedirectRequired('')).toBe(false);
    expect(httpsRedirectRequired('true')).toBe(true);
    expect(
      httpsRedirectTarget({
        required: false,
        secure: false,
        host: 'kayan.example',
        url: '/settings',
      }),
    ).toBeNull();
  });

  it('moves an insecure request to the same address over TLS', () => {
    expect(
      httpsRedirectTarget({
        required: true,
        secure: false,
        host: 'kayan.example',
        url: '/data/import?x=1',
      }),
    ).toBe('https://kayan.example/data/import?x=1');
  });

  it('leaves the proxy a route it can probe over plain HTTP', () => {
    expect(
      httpsRedirectTarget({
        required: true,
        secure: false,
        host: 'kayan.example',
        url: '/api/v1/health',
      }),
    ).toBeNull();
  });

  it('does not redirect what already came over TLS, nor what has no host', () => {
    expect(
      httpsRedirectTarget({ required: true, secure: true, host: 'h', url: '/x' }),
    ).toBeNull();
    expect(
      httpsRedirectTarget({ required: true, secure: false, url: '/x' }),
    ).toBeNull();
  });
});

describe('what the server says when it starts', () => {
  it('names the real LAN numbers rather than 0.0.0.0', () => {
    const lines = describeAccess({
      port: 3000,
      host: '0.0.0.0',
      lan: ['192.168.1.20'],
      proxy: false,
      requireHttps: false,
    });
    const all = lines.join('\n');
    expect(all).toContain('http://192.168.1.20:3000');
    expect(all).toContain('http://localhost:3000');
    expect(all).not.toContain('0.0.0.0:3000');
    expect(all).toContain('firewall');
  });

  it('warns about the pairing that locks an office out', () => {
    // Redirecting to HTTPS while no proxy is trusted is how "the whole office
    // cannot open the program" happens after one well-meant setting.
    const lines = describeAccess({
      port: 3000,
      host: '0.0.0.0',
      lan: [],
      proxy: false,
      requireHttps: true,
    });
    expect(lines.join('\n')).toContain('no proxy is trusted');
  });

  it('says plainly when the program is a one-machine desktop copy', () => {
    const lines = describeAccess({
      port: 3000,
      host: '127.0.0.1',
      lan: ['192.168.1.20'],
      proxy: 'loopback',
      requireHttps: false,
    });
    expect(lines.join('\n')).toContain('only this machine can reach the program');
    expect(lines.join('\n')).not.toContain('192.168.1.20');
    // A trusted proxy means the warning about the rate limiter is not true.
    expect(lines.join('\n')).not.toContain('No proxy trusted');
  });

  it('lists the machine’s own addresses and not the loopback', () => {
    expect(
      lanAddresses({
        eth0: [
          { family: 'IPv4', address: '192.168.1.20', internal: false },
          { family: 'IPv4', address: '127.0.0.1', internal: true },
          { family: 'IPv6', address: 'fe80::1', internal: false },
        ],
        lo: [{ family: 'IPv4', address: '127.0.0.1', internal: true }],
      } as never),
    ).toEqual(['192.168.1.20']);
  });
});

import { UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

import { AllowQueryToken } from '../decorators/allow-query-token.decorator';
import { DOWNLOAD_TICKET_TYPE } from '../download-ticket';
import { JwtAuthGuard } from './jwt-auth.guard';

/// The guard decides what a credential is allowed to travel in. These are the
/// rules that keep a sign-in token out of an address, and a download ticket
/// out of everything else.
describe('JwtAuthGuard', () => {
  const SECRET = 'test-secret';
  const jwt = new JwtService({ secret: SECRET });
  const original = process.env.JWT_ACCESS_SECRET;

  beforeAll(() => {
    process.env.JWT_ACCESS_SECRET = SECRET;
  });

  afterAll(() => {
    if (original === undefined) delete process.env.JWT_ACCESS_SECRET;
    else process.env.JWT_ACCESS_SECRET = original;
  });

  const payload = {
    sub: 'u1',
    username: 'admin',
    companyId: 'c1',
    branchId: null,
    isSuperAdmin: true,
    permissions: ['admin.company.manage'],
  };

  let accessToken = '';
  let ticket = '';

  beforeAll(async () => {
    accessToken = await jwt.signAsync(payload, { secret: SECRET });
    ticket = await jwt.signAsync(
      { ...payload, typ: DOWNLOAD_TICKET_TYPE },
      { secret: SECRET, expiresIn: 60 },
    );
  });

  /// A minimal stand-in for what Nest hands the guard.
  function context(options: {
    headers?: Record<string, string>;
    query?: Record<string, unknown>;
    allowQueryToken?: boolean;
  }) {
    const request: Record<string, unknown> = {
      headers: options.headers ?? {},
      query: options.query ?? {},
    };
    return {
      request,
      execution: {
        switchToHttp: () => ({
          getRequest: () => request,
        }),
        getHandler: () => (options.allowQueryToken ? decorated : plain),
        getClass: () => class Target {},
      } as unknown as import('@nestjs/common').ExecutionContext,
    };
  }

  class Target {}
  function plain() {}
  function decorated() {}
  AllowQueryToken()(decorated);

  function guard() {
    return new JwtAuthGuard(
      new (require('@nestjs/core').Reflector)(),
      jwt,
    );
  }

  it('accepts the sign-in token from the Authorization header', async () => {
    const { request, execution } = context({
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(await guard().canActivate(execution)).toBe(true);
    expect((request as { user?: unknown }).user).toMatchObject({
      userId: 'u1',
      companyId: 'c1',
    });
  });

  it('refuses a request with no credentials at all', async () => {
    await expect(guard().canActivate(context({}).execution)).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('refuses the sign-in token when it turns up in the address', async () => {
    // The whole point: an address is written into history and logs, and a
    // sign-in token is good for every route this person can reach. The
    // parameter is there for a ticket; pasting a sign-in token into it
    // must not work.
    const { execution } = context({
      query: { ticket: accessToken },
      allowQueryToken: true,
    });
    await expect(guard().canActivate(execution)).rejects.toThrow(
      /Only a download ticket may travel in the address/,
    );
  });

  it('no longer recognises the old ?token= parameter at all', async () => {
    // A leftover address from an older build must be dead, not quietly
    // upgraded: the parameter is gone, so there is nothing to read.
    const { execution } = context({
      query: { token: accessToken },
      allowQueryToken: true,
    });
    await expect(guard().canActivate(execution)).rejects.toThrow(
      /Missing bearer token/,
    );
  });

  it('refuses a ticket on a route that does not allow one in the address', async () => {
    const { execution } = context({ query: { ticket } });
    await expect(guard().canActivate(execution)).rejects.toThrow(
      /does not accept credentials in the address/,
    );
  });

  it('accepts a ticket in the address on a route that asks for one', async () => {
    const { request, execution } = context({
      query: { ticket },
      allowQueryToken: true,
    });
    expect(await guard().canActivate(execution)).toBe(true);
    expect((request as { user?: unknown }).user).toMatchObject({
      userId: 'u1',
    });
  });

  it('refuses a ticket that was sent as a bearer token instead', async () => {
    // A ticket is spent by a browser following an address. Handing it back as
    // a bearer token would make it a general-purpose credential.
    const { execution } = context({
      headers: { authorization: `Bearer ${ticket}` },
    });
    await expect(guard().canActivate(execution)).rejects.toThrow(
      /only works in an address/,
    );
  });

  it('refuses a token signed with another secret', async () => {
    const forged = await jwt.signAsync(payload, { secret: 'another-secret' });
    const { execution } = context({
      headers: { authorization: `Bearer ${forged}` },
    });
    await expect(guard().canActivate(execution)).rejects.toThrow(
      'Invalid or expired token',
    );
  });
});

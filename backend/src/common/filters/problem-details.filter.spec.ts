import { ArgumentsHost, NotFoundException } from '@nestjs/common';

import { ProblemDetailsFilter } from './problem-details.filter';

/**
 * A fake response that behaves like a real one where it matters: once the
 * headers have gone, writing again throws, exactly as Node's ServerResponse
 * does.
 */
function fakeResponse(options: { headersSent?: boolean; writableEnded?: boolean }) {
  const calls: Array<{ status?: number; body?: unknown; ended?: boolean }> = [];
  const status = (code: number) => {
    calls.push({ status: code });
    return {
      json: (body: unknown) => {
        if (options.headersSent) {
          throw new Error('Cannot set headers after they are sent to the client');
        }
        calls.push({ body });
      },
    };
  };
  return {
    calls,
    response: {
      headersSent: options.headersSent ?? false,
      writableEnded: options.writableEnded ?? false,
      status,
      end: () => calls.push({ ended: true }),
    },
  };
}

function fakeHost(response: unknown, request: unknown = {}): ArgumentsHost {
  return {
    switchToHttp: () => ({
      getResponse: () => response,
      getRequest: () => request,
    }),
  } as unknown as ArgumentsHost;
}

describe('the filter that writes every failure', () => {
  it('answers with the server’s own sentence, never a stack trace', () => {
    const { calls, response } = fakeResponse({});
    new ProblemDetailsFilter().catch(
      new NotFoundException('That account is not in the chart.'),
      fakeHost(response, { method: 'GET', originalUrl: '/api/v1/accounts/9' }),
    );

    expect(calls[0].status).toBe(404);
    expect(calls[1].body).toMatchObject({
      status: 404,
      detail: 'That account is not in the chart.',
    });
  });

  it('gives an unexplained failure a reference it can be found by', () => {
    const { calls, response } = fakeResponse({});
    new ProblemDetailsFilter().catch(
      new Error('something nobody expected'),
      fakeHost(response, { method: 'GET', originalUrl: '/api/v1/things' }),
    );

    const body = calls[1].body as { detail: string; errorId?: string };
    expect(calls[0].status).toBe(500);
    expect(body.detail).toBe('Unexpected server error');
    expect(body.errorId).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('says nothing at all when the reply has already gone', () => {
    // The failure that hid behind "Cannot set headers after they are sent"
    // was a second error arriving after the browser had been answered - a
    // screen that polls, or a request the browser gave up on. Trying to
    // report it is what buried the first one.
    const { calls, response } = fakeResponse({ headersSent: true });
    const filter = new ProblemDetailsFilter();

    expect(() =>
      filter.catch(new Error('the browser went away'), fakeHost(response)),
    ).not.toThrow();
    expect(calls.some((call) => call.body !== undefined)).toBe(false);
  });

  it('closes off a reply that was left open rather than leaving it hanging', () => {
    const { calls, response } = fakeResponse({ headersSent: true });
    new ProblemDetailsFilter().catch(new Error('too late'), fakeHost(response));
    expect(calls.some((call) => call.ended === true)).toBe(true);
  });

  it('never throws while reporting a failure, whatever goes wrong writing it', () => {
    const response = {
      headersSent: false,
      writableEnded: false,
      status: () => {
        throw new Error('the socket is gone');
      },
    };
    expect(() =>
      new ProblemDetailsFilter().catch(new Error('boom'), fakeHost(response)),
    ).not.toThrow();
  });
});

import { existsSync } from 'node:fs';
import { join } from 'node:path';

import { ValidationPipe, Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NextFunction, Request, Response } from 'express';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';
import {
  allowsOrigin,
  configuredOrigins as corsConfiguredOrigins,
} from './common/config/cors';
import { secretsProblem as jwtSecretsProblem } from './common/config/jwt-secrets';
import {
  clientSecurityHeaders,
  describeAccess,
  hstsEnabled,
  hstsMaxAgeSeconds,
  httpsRedirectRequired,
  httpsRedirectTarget,
  lanAddresses,
  proxyTrust,
  proxyTrustWarning,
} from './common/config/network';
import { ProblemDetailsFilter } from './common/filters/problem-details.filter';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
  });
  const logger = new Logger('Bootstrap');

  // Signing keys first. Without them the program can serve its own login
  // screen and then fail on the first sign-in with a message that names
  // nothing, so the check belongs here, at start-up, where it is read by the
  // person who started it rather than by the person trying to sign in.
  //
  // On a real installation that is a reason not to start at all: a program
  // that cannot issue a token is not a program anyone can use. While
  // developing, it is only a warning, because a checkout with no .env is a
  // normal thing to have.
  const secretsProblem = jwtSecretsProblem();
  if (secretsProblem) {
    if (process.env.NODE_ENV === 'production') {
      logger.error(secretsProblem);
      throw new Error(secretsProblem);
    }
    logger.warn(secretsProblem);
  }

  app.setGlobalPrefix('api/v1');

  // Reject unknown properties so a typo cannot silently create a half-formed
  // financial document.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  app.useGlobalFilters(new ProblemDetailsFilter());

  // A browser only lets a page call this API when the reply carries an
  // Access-Control-Allow-Origin header naming that page's origin. The Flutter
  // web dev server chooses the port it serves the client on, so a hard list of
  // ports breaks sign-in with a misleading "cannot reach the server" error.
  // Outside production every localhost origin is therefore accepted; in
  // production only the origins listed in CORS_ORIGINS are.
  const configuredOrigins = corsConfiguredOrigins(process.env.CORS_ORIGINS);
  const isProduction = process.env.NODE_ENV === 'production';

  app.enableCors({
    origin: (
      origin: string | undefined,
      callback: (err: Error | null, allow?: boolean) => void,
    ) => {
      // The rule itself lives in one place and is tested there: see
      // common/config/cors.ts.
      if (allowsOrigin(origin, configuredOrigins, isProduction)) {
        return callback(null, true);
      }
      logger.warn(`Blocked CORS request from origin: ${origin}`);
      return callback(null, false);
    },
    credentials: true,
  });

  // Who is calling, and over what.
  //
  // Behind a TLS-terminating proxy - the only sane way to let someone outside
  // the building in - every request arrives from the proxy's address over the
  // proxy's port. Left as it is, the rate limiter counts the whole office as
  // one person, `req.secure` is false while the browser is on HTTPS, and the
  // host a redirect is built from is the internal one. Express reads the
  // forwarded headers for all three, but only when it is told which proxies to
  // believe: `TRUST_PROXY=loopback` for a proxy on this machine, `true` when
  // nothing else can reach this port, or a count of the proxies in front.
  const proxy = proxyTrust();
  const proxyWarning = proxyTrustWarning();
  if (proxyWarning) logger.warn(proxyWarning);
  if (proxy !== false) {
    app.set('trust proxy', proxy);
  }

  // The headers every answer carries, and the one redirect an HTTPS-only
  // deployment asks for. Written here rather than in a package because the
  // whole list is four lines and a package would add a dependency that has to
  // be watched for the same four lines.
  const requireHttps = httpsRedirectRequired();
  const sendHsts = hstsEnabled();
  const hstsMaxAge = hstsMaxAgeSeconds();
  app.use((request: Request, response: Response, next: NextFunction) => {
    const secure = request.secure === true || request.protocol === 'https';
    for (const [name, value] of Object.entries(
      clientSecurityHeaders({ secure, hsts: sendHsts, hstsMaxAgeSeconds: hstsMaxAge }),
    )) {
      response.setHeader(name, value);
    }
    const away = httpsRedirectTarget({
      required: requireHttps,
      secure,
      host: request.headers.host,
      url: request.originalUrl ?? request.url,
    });
    if (away) {
      // 308 rather than 301 or 302: it keeps the method and the body, so a
      // signed POST that is sent to the wrong port is not quietly turned into
      // a GET that says nothing useful when it fails.
      response.redirect(308, away);
      return;
    }
    next();
  });

  // If a built copy of the web client sits next to the API, serve it from the
  // same address. One origin means no CORS, no second port to remember, and the
  // browser address is the address of the program itself.
  //
  // Checked in order: explicit env var -> relative to backend -> repo root -> dist bundle.
  const candidateWebRoots = [
    process.env.KAYAN_WEB_ROOT,
    join(process.cwd(), '..', 'build', 'web'),
    join(process.cwd(), 'build', 'web'),
    join(__dirname, '..', '..', 'build', 'web'),
    join(__dirname, '..', 'web'),
  ].filter(Boolean) as string[];

  const webRoot = candidateWebRoots.find((dir) =>
    existsSync(join(dir, 'index.html')),
  );

  if (webRoot) {
    app.useStaticAssets(webRoot);
    // Any other path that is not part of the API belongs to the client's own
    // routing, so hand back the page and let the client route it.
    const server = app.getHttpAdapter().getInstance();
    server.get(
      /^\/(?!api\/).*/,
      (
        _request: unknown,
        response: { sendFile: (path: string) => void },
      ) => response.sendFile(join(webRoot, 'index.html')),
    );
    logger.log(`Serving the web client from ${webRoot}`);
  } else {
    logger.log(
      'No web build found; the client is served by its own dev server',
    );
  }

  // Where the API listens.
  //
  // The default is every interface, so a server installation is reachable from
  // the other devices on the same network (phones, tablets, a second desk).
  // A desktop installation sets HOST=127.0.0.1: there the API is a private
  // part of one program on one machine, and nothing else should be able to
  // reach it.
  const port = Number(process.env.PORT ?? 3000);
  const host = process.env.HOST ?? '0.0.0.0';
  await app.listen(port, host);
  logger.log(`API listening on http://${host}:${port}/api/v1`);
  for (const line of describeAccess({
    port,
    host,
    lan: lanAddresses(),
    proxy,
    requireHttps,
  })) {
    logger.log(line);
  }
  // A line the desktop shell can wait for, in addition to the health route.
  logger.log(`KAYAN-API-READY port=${port} host=${host}`);
}
void bootstrap();

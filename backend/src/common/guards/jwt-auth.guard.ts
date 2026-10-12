import {
  CanActivate,
  ExecutionContext,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { accessSecret } from '../config/jwt-secrets';
import { ALLOW_QUERY_TOKEN_KEY } from '../decorators/allow-query-token.decorator';
import { DOWNLOAD_TICKET_TYPE } from '../download-ticket';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { OPTIONAL_AUTH_KEY } from '../decorators/optional-auth.decorator';
import { AuthUser } from '../decorators/current-user.decorator';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<{
      headers: Record<string, string>;
      query?: Record<string, unknown>;
      user?: AuthUser;
    }>();

    const header = request.headers['authorization'] ?? '';
    const [scheme, headerToken] = header.split(' ');

    let token: string | null =
      scheme?.toLowerCase() === 'bearer' && headerToken ? headerToken : null;

    // A browser navigation - a download, or a print page opened in a new tab -
    // cannot send an Authorization header. Those few routes accept a
    // *download ticket* in the query string instead, and they opt in one by
    // one. A ticket is minted by the server for one minute and carries no
    // power beyond fetching the file it was minted for.
    const fromQuery = request.query?.ticket;
    if (!token) {
      const allowsQueryToken = this.reflector.getAllAndOverride<boolean>(
        ALLOW_QUERY_TOKEN_KEY,
        [context.getHandler(), context.getClass()],
      );
      if (!allowsQueryToken && typeof fromQuery === 'string' && fromQuery) {
        throw new UnauthorizedException(
          'This route does not accept credentials in the address. ' +
            'Send the Authorization header instead.',
        );
      }
      if (allowsQueryToken && typeof fromQuery === 'string' && fromQuery) {
        token = fromQuery;
      }
    }

    // Some routes are about the credential rather than protected by it -
    // `POST /auth/logout` above all. See @OptionalAuth() for why refusing
    // those is worse than it looks.
    const optionalAuth = this.reflector.getAllAndOverride<boolean>(
      OPTIONAL_AUTH_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (!token) {
      if (optionalAuth) return true;
      throw new UnauthorizedException('Missing bearer token');
    }

    try {
      const payload = await this.jwt.verifyAsync<{
        typ?: string;
        sub: string;
        username: string;
        companyId: string;
        branchId: string | null;
        isSuperAdmin: boolean;
        permissions: string[];
      }>(token, { secret: accessSecret() });

      // A sign-in token is only ever accepted from the Authorization header.
      // In an address it would be written into browser history, proxy logs
      // and the Referer of anything the page links to, and it would still be
      // good for every route this person can reach. A download ticket is the
      // only credential allowed to travel in an address, and it is refused
      // everywhere else.
      const travelledInTheAddress = token === fromQuery;
      if (travelledInTheAddress && payload.typ !== DOWNLOAD_TICKET_TYPE) {
        throw new UnauthorizedException(
          'Only a download ticket may travel in the address, and this is ' +
            'not one. Sign in again and ask for a fresh ticket.',
        );
      }
      if (!travelledInTheAddress && payload.typ === DOWNLOAD_TICKET_TYPE) {
        throw new UnauthorizedException(
          'A download ticket only works in an address, for the file it was ' +
            'minted for.',
        );
      }

      request.user = {
        userId: payload.sub,
        username: payload.username,
        companyId: payload.companyId,
        branchId: payload.branchId,
        isSuperAdmin: payload.isSuperAdmin,
        permissions: payload.permissions ?? [],
      };
      return true;
    } catch (error) {
      if (error instanceof ServiceUnavailableException) throw error;
      // On a route that asked for the principal only if there is one, a token
      // that no longer verifies is the expected case, not a failure.
      if (optionalAuth) return true;
      if (error instanceof UnauthorizedException) throw error;
      // Never echo the underlying JWT error: it leaks library internals.
      throw new UnauthorizedException('Invalid or expired token');
    }
  }
}

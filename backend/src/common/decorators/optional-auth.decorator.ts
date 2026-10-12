import { SetMetadata } from '@nestjs/common';

export const OPTIONAL_AUTH_KEY = 'optionalAuth';

/**
 * Read the principal if the request carries one, and do not refuse the request
 * if it does not.
 *
 * `POST /auth/logout` is the route that needs this. Ending a session is what
 * a client does the moment after it has thrown a spent token away, so very
 * often there is nothing left to present with the request. Answering that with
 * `401` is not a harmless detail either: a client that reads any `401` as "the
 * session has run out" answers its own sign-out with another sign-out, and the
 * two feed each other until the rate limit guarding that address is spent —
 * which is how every download in the app started failing one day.
 *
 * The route still honors whatever principal it is given, so a logout with a
 * live token revokes that session exactly as before.
 */
export const OptionalAuth = () => SetMetadata(OPTIONAL_AUTH_KEY, true);

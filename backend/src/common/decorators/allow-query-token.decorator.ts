import { SetMetadata } from '@nestjs/common';

export const ALLOW_QUERY_TOKEN_KEY = 'allowQueryToken';

/// Lets a route accept a *download ticket* as `?ticket=` instead of a bearer
/// header.
///
/// A print page opened in a new tab is a browser navigation, not an XHR: the
/// tab cannot carry an Authorization header. Without this the print button
/// could not work at all.
///
/// What travels in the address is deliberately not the sign-in token. It is a
/// ticket that lives for a minute, can only be spent here, and carries no
/// power beyond fetching the file it was minted for. A sign-in token lasts
/// fifteen minutes, works on every route this person can reach and, from a
/// browser history entry or a proxy log, would hand over the whole account.
///
/// Apply it to download and print routes only, and never to a route that
/// changes data.
export const AllowQueryToken = () => SetMetadata(ALLOW_QUERY_TOKEN_KEY, true);

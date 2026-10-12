import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Response } from 'express';

/**
 * Emits RFC 9457 problem-details responses and never leaks stack traces or
 * database errors to the client.
 *
 * Every failure that is not already an `HttpException` gets a short reference
 * — an `errorId` — which is printed in the server log next to the stack and
 * handed back to the caller. That is what makes a bare "Unexpected server
 * error" actionable: whoever reads the screen quotes the id, and the id finds
 * the exact line in the log. Nothing else about the failure (the connection
 * string, a token, a file path) is ever put in the response.
 *
 * Two families of errors are translated into plain speech instead:
 *
 *  * Multer's upload errors (`LIMIT_FILE_SIZE` and friends) — left alone they
 *    all reach the screen as an "Unexpected server error", which tells nobody
 *    that the file was simply too big;
 *  * a malformed `DATABASE_URL`, which surfaces as a `TypeError` deep inside a
 *    `new URL(...)` call and, untranslated, hides the real problem.
 */
@Catch()
export class ProblemDetailsFilter implements ExceptionFilter {
  private readonly logger = new Logger('HttpException');

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const response = context.getResponse<Response>();
    const request = context.getRequest<{
      method?: string;
      originalUrl?: string;
      url?: string;
      route?: { path?: string };
    }>();

    let status: number;
    let detail = 'Unexpected server error';
    let extra: Record<string, unknown> = {};

    const translated = this.translate(exception);
    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse();
      if (typeof body === 'string') {
        detail = body;
      } else if (typeof body === 'object' && body !== null) {
        const b = body as Record<string, unknown>;
        detail = Array.isArray(b.message)
          ? (b.message as string[]).join('; ')
          : String(b.message ?? detail);
        if (b.errors) extra = { errors: b.errors };
      }
    } else if (translated) {
      status = translated.status;
      detail = translated.detail;
      this.logger.warn(
        `${translated.reason}: ${exception instanceof Error ? exception.message : String(exception)}`,
      );
    } else {
      status = HttpStatus.INTERNAL_SERVER_ERROR;
      const errorId = randomUUID();
      extra = { errorId };
      // The route pattern rather than the real URL: a real URL can carry a
      // token or a customer name, and it must not end up in a log file.
      const route = request.route?.path;
      const where = [
        request.method ?? '?',
        request.originalUrl ?? request.url ?? '?',
      ].join(' ');
      this.logger.error(
        `Unhandled exception ${errorId} on ${where}` +
          (route ? ` (route ${route})` : ''),
        exception instanceof Error ? exception.stack : String(exception),
      );
    }

    response.status(status).json({
      type: 'about:blank',
      title: HttpStatus[status] ?? 'Error',
      status,
      detail,
      ...extra,
    });
  }

  /// Known non-HTTP failures, turned into something a person can act on.
  private translate(
    exception: unknown,
  ): { status: number; detail: string; reason: string } | null {
    const code = (exception as { code?: unknown } | null | undefined)?.code;

    if (code === 'LIMIT_FILE_SIZE') {
      return {
        status: HttpStatus.PAYLOAD_TOO_LARGE,
        detail:
          'The file is larger than this program accepts. Split it, or raise ' +
          'the limit for this installation, and try again.',
        reason: 'upload refused (file too large)',
      };
    }
    if (code === 'LIMIT_FILE_COUNT' || code === 'LIMIT_PART_COUNT') {
      return {
        status: HttpStatus.PAYLOAD_TOO_LARGE,
        detail: 'The upload has more parts than this program accepts.',
        reason: 'upload refused (too many parts)',
      };
    }
    if (code === 'LIMIT_UNEXPECTED_FILE') {
      return {
        status: HttpStatus.BAD_REQUEST,
        detail:
          'The upload did not arrive in the field the server expects. ' +
          'Send it again from the screen that asks for it.',
        reason: 'upload refused (unexpected field)',
      };
    }

    if (exception instanceof TypeError || exception instanceof URIError) {
      const message =
        exception instanceof Error ? exception.message : String(exception);
      if (/Invalid URL|must be of type string|Failed to parse URL/i.test(message)) {
        return {
          status: HttpStatus.SERVICE_UNAVAILABLE,
          detail:
            'The database address this server was started with cannot be ' +
            'read. Check DATABASE_URL and restart the server. ' +
            'Nothing was changed.',
          reason: 'the database address in the configuration is not readable',
        };
      }
    }

    return null;
  }
}

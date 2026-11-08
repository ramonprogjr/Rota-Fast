import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { ThrottlerException } from '@nestjs/throttler';
import type { Request, Response } from 'express';
import { AppException } from '../exceptions/app.exception';

/** Formato único de erro da API. */
export interface ErrorBody {
  statusCode: number;
  error: string;
  message: string;
  details?: unknown;
  path: string;
  timestamp: string;
  requestId?: string;
}

const DEFAULT_CODES: Record<number, string> = {
  400: 'BAD_REQUEST',
  401: 'UNAUTHORIZED',
  403: 'FORBIDDEN',
  404: 'NOT_FOUND',
  405: 'METHOD_NOT_ALLOWED',
  409: 'CONFLICT',
  413: 'PAYLOAD_TOO_LARGE',
  422: 'UNPROCESSABLE_ENTITY',
  429: 'RATE_LIMITED',
};

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('HttpExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<Request & { requestId?: string }>();
    const body = this.toBody(exception, req);
    if (body.statusCode >= 500) {
      // Nunca devolve stack nem mensagem interna para o cliente.
      this.logger.error(
        `${req.method} ${req.url} -> ${body.statusCode} [${body.requestId ?? '-'}]`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    }
    res.status(body.statusCode).json(body);
  }

  private toBody(exception: unknown, req: Request & { requestId?: string }): ErrorBody {
    const base = {
      path: req.originalUrl ?? req.url,
      timestamp: new Date().toISOString(),
      requestId: req.requestId,
    };
    if (exception instanceof AppException) {
      return {
        statusCode: exception.getStatus(),
        error: exception.code,
        message: exception.message,
        ...(exception.details !== undefined ? { details: exception.details } : {}),
        ...base,
      };
    }
    if (exception instanceof ThrottlerException) {
      return { statusCode: 429, error: 'RATE_LIMITED', message: 'Muitas requisições. Tente de novo em instantes.', ...base };
    }
    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const response = exception.getResponse();
      if (status === HttpStatus.BAD_REQUEST && typeof response === 'object' && response !== null) {
        const messages = (response as { message?: unknown }).message;
        if (Array.isArray(messages)) {
          return {
            statusCode: 400,
            error: 'VALIDATION_FAILED',
            message: 'Dados inválidos.',
            details: messages,
            ...base,
          };
        }
      }
      return {
        statusCode: status,
        error: DEFAULT_CODES[status] ?? 'HTTP_ERROR',
        message: exception.message,
        ...base,
      };
    }
    return {
      statusCode: 500,
      error: 'INTERNAL_ERROR',
      message: 'Erro interno. Tente de novo.',
      ...base,
    };
  }
}

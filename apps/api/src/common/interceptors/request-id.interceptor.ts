import { CallHandler, ExecutionContext, Injectable, Logger, NestInterceptor } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';
import { Observable, tap } from 'rxjs';

const SAFE_ID = /^[A-Za-z0-9-]{8,64}$/;

/**
 * Middleware: propaga `x-request-id` (ou cria um). Roda antes dos guards, então
 * até um 401 sai com o id.
 */
export function requestIdMiddleware(req: Request & { requestId?: string }, res: Response, next: NextFunction): void {
  const incoming = req.header('x-request-id');
  const id = incoming && SAFE_ID.test(incoming) ? incoming : randomUUID();
  req.requestId = id;
  res.setHeader('x-request-id', id);
  next();
}

/** Loga método, rota (sem query string, que pode ter dados) e duração. */
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('HTTP');

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = context.switchToHttp().getRequest<Request & { requestId?: string }>();
    const started = Date.now();
    return next.handle().pipe(
      tap(() => {
        this.logger.log(`${req.method} ${req.path} ${Date.now() - started}ms [${req.requestId ?? '-'}]`);
      }),
    );
  }
}

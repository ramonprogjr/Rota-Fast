import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * Erro de negócio com código estável. O filtro global transforma em
 * `{ statusCode, error, message, details, path, timestamp, requestId }`.
 */
export class AppException extends HttpException {
  constructor(
    status: HttpStatus,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super({ code, message, details }, status);
  }
}

/** 404 também para recurso de outro usuário: não revela que existe. */
export class NotFoundAppException extends AppException {
  constructor(resource: string) {
    super(HttpStatus.NOT_FOUND, `${resource.toUpperCase()}_NOT_FOUND`, `${resource} não encontrado(a).`);
  }
}

export class ConflictAppException extends AppException {
  constructor(code: string, message: string, details?: unknown) {
    super(HttpStatus.CONFLICT, code, message, details);
  }
}

export class UnprocessableAppException extends AppException {
  constructor(code: string, message: string, details?: unknown) {
    super(HttpStatus.UNPROCESSABLE_ENTITY, code, message, details);
  }
}

export class UnauthorizedAppException extends AppException {
  constructor(code: string, message: string) {
    super(HttpStatus.UNAUTHORIZED, code, message);
  }
}

export class ServiceUnavailableAppException extends AppException {
  constructor(code: string, message: string) {
    super(HttpStatus.SERVICE_UNAVAILABLE, code, message);
  }
}

export class ForbiddenAppException extends AppException {
  constructor(code: string, message: string) {
    super(HttpStatus.FORBIDDEN, code, message);
  }
}

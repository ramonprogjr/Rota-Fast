import { type INestApplication, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, type OpenAPIObject, SwaggerModule } from '@nestjs/swagger';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { requestIdMiddleware } from './common/interceptors/request-id.interceptor';

export const API_PREFIX = 'v1';

/**
 * Configuração comum ao main, aos testes e/2e e ao export do OpenAPI:
 * prefixo /v1, validação estrita, formato único de erro.
 */
export function configureApp(app: INestApplication, options: { corsOrigins?: string[] } = {}): INestApplication {
  app.use(requestIdMiddleware);
  app.setGlobalPrefix(API_PREFIX);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      stopAtFirstError: false,
    }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());
  if (options.corsOrigins?.length) {
    app.enableCors({ origin: options.corsOrigins, credentials: false });
  }
  return app;
}

export function buildOpenApi(app: INestApplication): OpenAPIObject {
  const config = new DocumentBuilder()
    .setTitle('Rota Max API')
    .setDescription(
      'Conta opcional, backup e sincronização do app Rota Max (offline-first). ' +
        'Autenticação: JWT do Supabase Auth em `Authorization: Bearer`. ' +
        'Erros: `{ statusCode, error, message, details?, path, timestamp, requestId }`.',
    )
    .setVersion('1.0.0')
    .addBearerAuth({ type: 'http', scheme: 'bearer', bearerFormat: 'JWT' })
    .addServer('/')
    .build();
  const document = SwaggerModule.createDocument(app, config, {
    operationIdFactory: (controllerKey, methodKey) => `${controllerKey.replace(/Controller$/, '')}_${methodKey}`,
  });
  addErrorResponses(document);
  return document;
}

/** Documenta o formato único de erro em todas as operações. */
function addErrorResponses(document: OpenAPIObject): void {
  document.components ??= {};
  document.components.schemas ??= {};
  document.components.schemas.ErrorResponse = {
    type: 'object',
    required: ['statusCode', 'error', 'message', 'path', 'timestamp'],
    properties: {
      statusCode: { type: 'integer', example: 404 },
      error: { type: 'string', description: 'Código estável', example: 'ROUTE_NOT_FOUND' },
      message: { type: 'string', example: 'route não encontrado(a).' },
      details: { description: 'Detalhes (ex.: campos inválidos, retrato do servidor em conflito)' },
      path: { type: 'string', example: '/v1/routes/…' },
      timestamp: { type: 'string', format: 'date-time' },
      requestId: { type: 'string' },
    },
  };
  const ref = { $ref: '#/components/schemas/ErrorResponse' };
  const error = (description: string) => ({ description, content: { 'application/json': { schema: ref } } });
  for (const path of Object.values(document.paths)) {
    for (const method of ['get', 'post', 'patch', 'put', 'delete'] as const) {
      const operation = path[method];
      if (!operation) continue;
      const isPublic = !operation.security?.length;
      operation.responses = {
        ...operation.responses,
        ...(isPublic ? {} : { '401': error('Token ausente, inválido ou expirado') }),
        '400': error('Dados inválidos (VALIDATION_FAILED)'),
        '429': error('Muitas requisições (RATE_LIMITED)'),
        ...(isPublic ? {} : { '404': error('Não encontrado — inclusive recurso de outro usuário') }),
        ...(method === 'get' || isPublic ? {} : { '409': error('Conflito de versão/estado'), '422': error('Regra de negócio') }),
      };
    }
  }
}

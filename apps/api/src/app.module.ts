import { type DynamicModule, Global, Module, type Provider } from '@nestjs/common';
import { APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { JWT_VERIFIER, type JwtVerifier } from './auth/jwt-verifier';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { LoggingInterceptor } from './common/interceptors/request-id.interceptor';
import { DeliveriesModule } from './deliveries/deliveries.module';
import { DevicesModule } from './devices/devices.module';
import { HealthModule } from './health/health.module';
import { OptimizationModule } from './optimization/optimization.module';
import { OrganizationsModule } from './organizations/organizations.module';
import { PaymentsModule } from './payments/payments.module';
import { DATABASE, type Database } from './persistence/data-store';
import { RoutesModule } from './routes/routes.module';
import { SubscriptionsModule } from './subscriptions/subscriptions.module';
import { SynchronizationModule } from './synchronization/synchronization.module';
import { UsersModule } from './users/users.module';

export interface AppOptions {
  /** PrismaDatabase em produção; MemoryDatabase em testes e no export do OpenAPI. */
  database: Database;
  /** JoseJwtVerifier.forSupabase em produção; par de chaves local nos testes. */
  verifier: JwtVerifier;
  rateLimitPerMinute?: number;
  /** Log por requisição (desligado nos testes). */
  requestLogging?: boolean;
}

/** Infra compartilhada por todos os módulos (banco e verificador de JWT). */
@Global()
@Module({})
class CoreModule {
  static register(options: AppOptions): DynamicModule {
    const providers: Provider[] = [
      { provide: DATABASE, useValue: options.database },
      { provide: JWT_VERIFIER, useValue: options.verifier },
    ];
    return { module: CoreModule, providers, exports: providers };
  }
}

const FEATURE_MODULES = [
  HealthModule,
  UsersModule,
  DevicesModule,
  OrganizationsModule,
  RoutesModule,
  DeliveriesModule,
  OptimizationModule,
  SynchronizationModule,
  SubscriptionsModule,
  PaymentsModule,
];

@Module({})
export class AppModule {
  static forRoot(options: AppOptions): DynamicModule {
    return {
      module: AppModule,
      imports: [
        CoreModule.register(options),
        ThrottlerModule.forRoot([{ name: 'default', ttl: 60_000, limit: options.rateLimitPerMinute ?? 120 }]),
        ...FEATURE_MODULES,
      ],
      providers: [
        // Ordem importa: rate limit antes da autenticação.
        { provide: APP_GUARD, useClass: ThrottlerGuard },
        { provide: APP_GUARD, useClass: JwtAuthGuard },
        ...(options.requestLogging ? [{ provide: APP_INTERCEPTOR, useClass: LoggingInterceptor }] : []),
      ],
    };
  }
}

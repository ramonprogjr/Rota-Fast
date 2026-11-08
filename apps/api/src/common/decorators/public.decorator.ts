import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

/** Rota sem autenticação (ex.: /v1/health). Todas as outras exigem JWT. */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

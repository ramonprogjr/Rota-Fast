import { Controller, Get } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthPrincipal } from '../auth/jwt-verifier';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { SubscriptionResponse } from './dto/subscription.dto';
import { SubscriptionsService } from './subscriptions.service';

@ApiTags('subscriptions')
@ApiBearerAuth()
@Controller('subscriptions')
export class SubscriptionsController {
  constructor(private readonly subscriptions: SubscriptionsService) {}

  /** Plano do usuário. Na v1 é sempre o free (cobrança desligada). */
  @Get('me')
  me(@CurrentUser() user: AuthPrincipal): Promise<SubscriptionResponse> {
    return this.subscriptions.getForUser(user.userId);
  }
}

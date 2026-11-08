import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthPrincipal } from '../auth/jwt-verifier';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { OptimizationPreviewDto, OptimizationPreviewResponse } from './dto/optimization.dto';
import { OptimizationService } from './optimization.service';

@ApiTags('optimization')
@ApiBearerAuth()
@Controller('optimization')
export class OptimizationController {
  constructor(private readonly optimization: OptimizationService) {}

  /**
   * Ordem proposta (vizinho mais próximo + 2-opt, haversine × 1,3), respeitando
   * travas e posições fixas. Não altera a rota salva.
   */
  @Post('preview')
  @HttpCode(HttpStatus.OK)
  preview(@CurrentUser() user: AuthPrincipal, @Body() dto: OptimizationPreviewDto): Promise<OptimizationPreviewResponse> {
    return this.optimization.preview(user.userId, dto);
  }
}

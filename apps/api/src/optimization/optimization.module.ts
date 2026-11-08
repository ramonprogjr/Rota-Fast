import { Module } from '@nestjs/common';
import { OptimizationController } from './optimization.controller';
import { OptimizationService } from './optimization.service';

@Module({
  controllers: [OptimizationController],
  providers: [OptimizationService],
})
export class OptimizationModule {}

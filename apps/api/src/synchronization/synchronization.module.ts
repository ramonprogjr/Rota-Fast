import { Module } from '@nestjs/common';
import { DevicesModule } from '../devices/devices.module';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';

@Module({
  imports: [DevicesModule],
  controllers: [SyncController],
  providers: [SyncService],
})
export class SynchronizationModule {}

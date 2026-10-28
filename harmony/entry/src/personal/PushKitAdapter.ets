import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { pushService } from '@kit.PushKit';

export class PushKitAdapter {
  static readonly supported: boolean = true;
  static async getToken(context: common.UIAbilityContext): Promise<string> {
    await notificationManager.requestEnableNotification(context);
    return await pushService.getToken();
  }
  static async deleteToken(): Promise<void> { await pushService.deleteToken(); }
}

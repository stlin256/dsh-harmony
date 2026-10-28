import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BuildInfo } from './BuildInfo';

export class BackgroundMonitor {
  static notificationId(sessionId: string, state: string): number {
    return BackgroundMonitor.code(sessionId + ':' + state);
  }

  private static async action(sessionId: string): Promise<WantAgent> {
    return await wantAgent.getWantAgent({
      wants: [{ bundleName: BuildInfo.bundleName, abilityName: 'EntryAbility', parameters: { sessionId } }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: BackgroundMonitor.code(sessionId),
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  static async start(context: common.UIAbilityContext, sessionId: string): Promise<void> {
    const action = await BackgroundMonitor.action(sessionId);
    await backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, action);
  }

  static async stop(context: common.UIAbilityContext): Promise<void> {
    try { await backgroundTaskManager.stopBackgroundRunning(context); } catch (_) {}
  }

  static async notify(sessionId: string, title: string, text: string, id: number): Promise<void> {
    const action = await BackgroundMonitor.action(sessionId);
    const request: notificationManager.NotificationRequest = {
      id,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title.slice(0, 80), text: text.slice(0, 160) }
      },
      wantAgent: action
    };
    await new Promise<void>((resolve, reject) => {
      notificationManager.publish(request, (error) => { if (error) reject(error); else resolve(); });
    });
  }

  private static code(value: string): number {
    let hash = 0;
    for (let index = 0; index < value.length; index++) hash = ((hash << 5) - hash + value.charCodeAt(index)) | 0;
    return hash & 0x7fffffff;
  }
}

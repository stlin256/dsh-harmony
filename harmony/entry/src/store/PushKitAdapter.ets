import { common } from '@kit.AbilityKit';

/** AppGallery build: server push is tied to the maintainer's application identity. */
export class PushKitAdapter {
  static readonly supported: boolean = false;
  static async getToken(_context: common.UIAbilityContext): Promise<string> {
    throw new Error('Push Kit is disabled in the AppGallery build');
  }
  static async deleteToken(): Promise<void> {}
}

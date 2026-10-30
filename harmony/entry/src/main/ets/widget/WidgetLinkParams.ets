/** Explicit model for FormLink routing parameters under ArkTS object-literal rules. */
export class WidgetLinkParams {
  sessionId: string = '';
  pocketRoute: string = '';

  constructor(sessionId: string = '', pocketRoute: string = '') {
    this.sessionId = sessionId;
    this.pocketRoute = pocketRoute;
  }
}

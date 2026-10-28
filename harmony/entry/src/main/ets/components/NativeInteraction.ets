import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeFrame, NativeQuestion, NativeOption } from '../services/NativeSessionModel';

class Answer { id: string = ''; selected: string[] = []; custom: string = ''; }

/** Only a live, correlated Host request can enable these decision controls. */
@Component
export struct NativeInteraction {
  client: NativeHarnessClient = new NativeHarnessClient('');
  @Prop frame: NativeFrame = new NativeFrame();
  onDone: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private answers: Answer[] = [];
  @State private remaining: number = -1;
  private countdown: number = -1;
  private engaged: boolean = false;
  @State private busy: boolean = false;
  @State private unconfirmed: boolean = false;
  @State private error: string = '';

  aboutToAppear(): void {
    this.remaining = this.frame.remainingMs === undefined ? -1 : this.frame.remainingMs;
    if (this.remaining >= 0) this.countdown = setInterval(() => { this.remaining = Math.max(0, this.remaining - 1000); }, 1000);
    this.answers = (this.frame.request.questions || []).map((question: NativeQuestion) => {
      const answer = new Answer(); answer.id = question.id; return answer;
    });
  }
  aboutToDisappear(): void { clearInterval(this.countdown); }
  private engage(): void {
    if (this.engaged || this.remaining < 0 || this.frame.callId) return;
    this.engaged = true; clearInterval(this.countdown); this.remaining = -1;
    this.client.answer(JSON.stringify({ connectionId: this.frame.connectionId, eventId: this.frame.eventId, engage: true }))
      .catch(() => { this.unconfirmed = true; this.error = '问题状态已变化，请刷新核对'; });
  }
  private toggle(question: NativeQuestion, label: string): void {
    this.engage();
    this.answers = this.answers.map((answer: Answer) => {
      if (answer.id !== question.id) return answer;
      const next = new Answer(); next.id = answer.id; next.custom = answer.custom;
      next.selected = answer.selected.includes(label) ? answer.selected.filter((value: string) => value !== label) :
        question.multiSelect ? answer.selected.concat([label]) : [label];
      return next;
    });
  }
  private custom(id: string, text: string): void {
    this.engage();
    this.answers = this.answers.map((answer: Answer) => {
      if (answer.id !== id) return answer;
      const next = new Answer(); next.id = answer.id; next.selected = answer.selected; next.custom = text; return next;
    });
  }
  private selected(id: string, label: string): boolean {
    return this.answers.some((answer: Answer) => answer.id === id && answer.selected.includes(label));
  }
  private async submit(value: string, delegate: boolean = false): Promise<void> {
    if (this.busy || this.unconfirmed) return;
    this.busy = true; this.error = '';
    try {
      if (this.frame.callId) {
        if (!delegate) {
          const result = await this.client.operation(JSON.stringify({ operation: 'answerQuestion', sessionId: this.frame.connectionId, callId: this.frame.callId, answer: { answers: this.answers } }));
          if (result !== 'true') throw new Error('Question no longer answerable');
        }
      } else await this.client.answer(JSON.stringify({ connectionId: this.frame.connectionId, eventId: this.frame.eventId,
        delegate, value: this.frame.interaction === 'approval/request' ? value : { answers: this.answers } }));
      this.onDone();
    } catch (_) {
      this.unconfirmed = true;
      this.error = '决定结果未确认，请刷新核对请求状态；不会重复提交。';
    } finally { this.busy = false; }
  }
  build() {
    Column({ space: 10 }) {
      Text(this.frame.interaction === 'approval/request' ? '需要你的审批' : '需要你的回答').fontSize(16).fontWeight(FontWeight.Medium)
      Scroll() {
        Column({ space: 12 }) {
          if (this.frame.interaction === 'approval/request') {
            Text(this.frame.request.toolName).fontSize(14).fontWeight(FontWeight.Medium)
            Text(this.frame.request.reason || this.frame.request.displayReason?.zh || this.frame.request.displayReason?.en || '').fontSize(14).copyOption(CopyOptions.InApp)
            Row({ space: 12 }) {
              Button('拒绝').height(44).enabled(!this.busy && !this.unconfirmed).onClick(() => { this.submit('rejected'); })
              Button('允许一次').height(44).enabled(!this.busy && !this.unconfirmed).onClick(() => { this.submit('allowed-once'); })
            }
          } else {
            ForEach(this.frame.request.questions, (question: NativeQuestion) => {
              Column({ space: 8 }) {
                if (question.header) { Text(question.header).fontSize(12) }
                Text(question.question).fontSize(15).fontWeight(FontWeight.Medium)
                if (question.detail) { Text(question.detail).fontSize(13).copyOption(CopyOptions.InApp) }
                ForEach(question.options || [], (option: NativeOption) => {
                  Button({ type: ButtonType.Normal }) {
                    Column({ space: 4 }) {
                      Text((this.selected(question.id, option.label) ? '✓ ' : '') + option.label).fontSize(14)
                      if (option.description) { Text(option.description).fontSize(12) }
                    }.alignItems(HorizontalAlign.Start).width('100%').padding(10)
                  }.borderRadius(12).backgroundColor(this.selected(question.id, option.label) ? this.dark ? '#484A50' : '#DDE3ED' : this.dark ? '#353638' : '#F5F6F7')
                    .fontColor(this.dark ? '#F9FAFB' : '#0F1115').enabled(!this.busy && !this.unconfirmed)
                    .onClick(() => { this.toggle(question, option.label); })
                }, (option: NativeOption) => option.label)
                if (question.intent?.kind !== 'approval') {
                  TextArea({ placeholder: question.multiSelect ? '补充回答（可选）' : '自定义回答' }).height(80)
                    .onFocus(() => { this.engage(); }).onChange((text: string) => { this.custom(question.id, text); })
                }
              }.width('100%').alignItems(HorizontalAlign.Start)
            }, (question: NativeQuestion) => question.id)
            Button('提交回答').height(44).enabled(!this.busy && !this.unconfirmed).onClick(() => { this.submit(''); })
          }
          Button(this.frame.callId ? '稍后回答' : '交给其他客户端处理').height(44).enabled(!this.busy && !this.unconfirmed).onClick(() => { this.submit('', true); })
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ maxHeight: 320 })
      if (this.remaining >= 0) { Text('等待回答 · ' + Math.ceil(this.remaining / 1000) + ' 秒；开始作答后暂停倒计时').fontSize(12) }
      if (this.error) { Text(this.error).fontSize(12).fontColor(this.dark ? '#FF9393' : '#C53030') }
    }.padding(16).width('100%').alignItems(HorizontalAlign.Start).borderRadius(16)
      .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7').foregroundColor(this.dark ? '#F9FAFB' : '#0F1115')
  }
}

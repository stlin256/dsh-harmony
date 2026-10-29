import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeFrame, NativeQuestion, NativeOption } from '../services/NativeSessionModel';

class Answer { id: string = ''; selected: string[] = []; custom: string = ''; }
class AnswerPayload { answers: Answer[] = []; }
class OperationAnswerPayload {
  operation: string = 'answerQuestion';
  sessionId: string = '';
  callId: string = '';
  answer: AnswerPayload = new AnswerPayload();
}
class ApprovalSubmissionPayload {
  connectionId: string = '';
  eventId: string = '';
  delegate: boolean = false;
  value: string = '';
}
class QuestionSubmissionPayload {
  connectionId: string = '';
  eventId: string = '';
  delegate: boolean = false;
  value: AnswerPayload = new AnswerPayload();
}

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
          const payload = new OperationAnswerPayload();
          payload.sessionId = this.frame.connectionId;
          payload.callId = this.frame.callId;
          payload.answer.answers = this.answers;
          const result = await this.client.operation(JSON.stringify(payload));
          if (result !== 'true') throw new Error('Question no longer answerable');
        }
      } else if (this.frame.interaction === 'approval/request') {
        const payload = new ApprovalSubmissionPayload();
        payload.connectionId = this.frame.connectionId;
        payload.eventId = this.frame.eventId;
        payload.delegate = delegate;
        payload.value = value;
        await this.client.answer(JSON.stringify(payload));
      } else {
        const payload = new QuestionSubmissionPayload();
        payload.connectionId = this.frame.connectionId;
        payload.eventId = this.frame.eventId;
        payload.delegate = delegate;
        payload.value.answers = this.answers;
        await this.client.answer(JSON.stringify(payload));
      }
      this.onDone();
    } catch (_) {
      this.unconfirmed = true;
      this.error = '提交结果未确认，请刷新';
    } finally { this.busy = false; }
  }
  build() {
    Column({ space: 8 }) {
      Row({ space: 7 }) {
        Circle().width(7).height(7).fill(this.dark ? '#F0B84A' : '#A56A00')
        Text(this.frame.interaction === 'approval/request' ? '需要你的审批' : '需要你的回答').fontSize(15).fontWeight(FontWeight.Medium)
      }
      Scroll() {
        Column({ space: 10 }) {
          if (this.frame.interaction === 'approval/request') {
            Text(this.frame.request.toolName).fontSize(14).fontWeight(FontWeight.Medium)
            Text(this.frame.request.reason || this.frame.request.displayReason?.zh || this.frame.request.displayReason?.en || '').fontSize(14).copyOption(CopyOptions.InApp)
            Row({ space: 8 }) {
              Button('拒绝').height(38).borderRadius(9).backgroundColor(this.dark ? '#353638' : '#F5F6F7')
                .fontColor(this.dark ? '#F9FAFB' : '#0F1115').enabled(!this.busy && !this.unconfirmed)
                .onClick(() => { this.submit('rejected'); })
              Button('允许一次').height(38).borderRadius(9).backgroundColor(this.dark ? '#679EFE' : '#3964FE')
                .fontColor('#FFFFFF').enabled(!this.busy && !this.unconfirmed)
                .onClick(() => { this.submit('allowed-once'); })
            }
          } else {
            ForEach(this.frame.request.questions, (question: NativeQuestion) => {
              Column({ space: 6 }) {
                if (question.header) { Text(question.header).fontSize(12) }
                Text(question.question).fontSize(15).fontWeight(FontWeight.Medium)
                if (question.detail) { Text(question.detail).fontSize(13).copyOption(CopyOptions.InApp) }
                ForEach(question.options || [], (option: NativeOption) => {
                  Button({ type: ButtonType.Normal }) {
                    Column({ space: 4 }) {
                      Text((this.selected(question.id, option.label) ? '✓ ' : '') + option.label).fontSize(14)
                      if (option.description) { Text(option.description).fontSize(12) }
                    }.alignItems(HorizontalAlign.Start).width('100%').padding(8)
                  }.borderRadius(12).backgroundColor(this.selected(question.id, option.label) ? this.dark ? '#484A50' : '#DDE3ED' : this.dark ? '#353638' : '#F5F6F7')
                    .fontColor(this.dark ? '#F9FAFB' : '#0F1115').enabled(!this.busy && !this.unconfirmed)
                    .onClick(() => { this.toggle(question, option.label); })
                }, (option: NativeOption) => option.label)
                if (question.intent?.kind !== 'approval') {
                  TextArea({ placeholder: question.multiSelect ? '补充回答（可选）' : '自定义回答' }).height(68)
                    .onFocus(() => { this.engage(); }).onChange((text: string) => { this.custom(question.id, text); })
                }
              }.width('100%').alignItems(HorizontalAlign.Start)
            }, (question: NativeQuestion) => question.id)
            Button('提交回答').height(38).borderRadius(9).backgroundColor(this.dark ? '#679EFE' : '#3964FE')
              .fontColor('#FFFFFF').enabled(!this.busy && !this.unconfirmed).onClick(() => { this.submit(''); })
          }
          Button(this.frame.callId ? '稍后回答' : '交给其他客户端处理').height(38).borderRadius(9)
            .backgroundColor(Color.Transparent).fontColor(this.dark ? '#CFD3D6' : '#61666B')
            .enabled(!this.busy && !this.unconfirmed).onClick(() => { this.submit('', true); })
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ maxHeight: 320 })
      if (this.remaining >= 0) { Text('剩余 ' + Math.ceil(this.remaining / 1000) + ' 秒').fontSize(12) }
      if (this.error) { Text(this.error).fontSize(12).fontColor(this.dark ? '#FF9393' : '#C53030') }
    }.padding(12).width('100%').alignItems(HorizontalAlign.Start).borderRadius(14)
      .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7').foregroundColor(this.dark ? '#F9FAFB' : '#0F1115')
  }
}

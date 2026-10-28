import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { WidgetStore } from '../services/WidgetStore';

export default class PocketFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const id = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string;
    const temporary = want.parameters?.[formInfo.FormParam.TEMPORARY_KEY] === true;
    if (id && !temporary) WidgetStore.register(this.context, id);
    // Synchronous first frame; no network, credential access or background loop.
    return formBindingData.createFormBindingData(WidgetStore.data(this.context));
  }

  onCastToNormalForm(formId: string): void { WidgetStore.register(this.context, formId); }
  onRemoveForm(formId: string): void { WidgetStore.remove(this.context, formId); }
  onUpdateForm(formId: string): void {
    // The OS decides when to run this callback. Re-evaluate cached expiry only.
    formProvider.updateForm(formId, formBindingData.createFormBindingData(WidgetStore.data(this.context))).catch(() => {});
  }
  onAcquireFormState(_want: Want): formInfo.FormState { return formInfo.FormState.READY; }
}

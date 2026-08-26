<script setup>
import { ref, watchEffect } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from 'dashboard/routes/dashboard/settings/account/components/SectionLayout.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

const brandColor = ref('#2781F6');
const brandLogoUrl = ref('');
const isSaving = ref(false);

watchEffect(() => {
  brandColor.value = currentAccount.value?.settings?.brand_color || '#2781F6';
  brandLogoUrl.value = currentAccount.value?.settings?.brand_logo_url || '';
});

const save = async () => {
  isSaving.value = true;
  try {
    await updateAccount({
      brand_color: brandColor.value,
      brand_logo_url: brandLogoUrl.value,
    });
    useAlert(t('UP_SALES.BRANDING.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('UP_SALES.BRANDING.ERROR_MESSAGE'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="p-6 max-w-2xl">
    <SectionLayout
      :title="t('UP_SALES.BRANDING.TITLE')"
      :description="t('UP_SALES.BRANDING.DESCRIPTION')"
    >
      <div class="flex flex-col gap-4">
        <div>
          <label class="text-sm font-medium text-n-slate-12 mb-1 block">
            {{ t('UP_SALES.BRANDING.COLOR_LABEL') }}
          </label>
          <div class="flex items-center gap-3">
            <input
              v-model="brandColor"
              type="color"
              class="h-9 w-9 rounded border border-n-weak cursor-pointer"
            />
            <woot-input
              v-model="brandColor"
              type="text"
              placeholder="#2781F6"
              class="!mb-0 w-40"
            />
          </div>
        </div>

        <div>
          <woot-input
            v-model="brandLogoUrl"
            type="text"
            :label="t('UP_SALES.BRANDING.LOGO_LABEL')"
            :placeholder="t('UP_SALES.BRANDING.LOGO_PLACEHOLDER')"
            class="!mb-0 w-full"
          />
          <img
            v-if="brandLogoUrl"
            :src="brandLogoUrl"
            :alt="t('UP_SALES.BRANDING.LOGO_PREVIEW_ALT')"
            class="mt-2 h-8 object-contain"
          />
        </div>

        <div>
          <woot-button :is-loading="isSaving" @click="save">
            {{ t('UP_SALES.BRANDING.SAVE_BUTTON') }}
          </woot-button>
        </div>
      </div>
    </SectionLayout>
  </div>
</template>

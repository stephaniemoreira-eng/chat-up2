<script setup>
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col items-center justify-center gap-2 p-12 text-center">
    <span class="text-base font-medium text-n-slate-12">
      {{ t('CRM.EMPTY_STATE.TITLE') }}
    </span>
    <span class="text-sm text-n-slate-11">
      {{ t('CRM.EMPTY_STATE.SUBTITLE') }}
    </span>
  </div>
</template>

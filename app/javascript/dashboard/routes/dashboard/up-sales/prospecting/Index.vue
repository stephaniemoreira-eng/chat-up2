<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ProspectingAPI from 'dashboard/api/sales/prospecting';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import AutoSearchPanel from 'dashboard/routes/dashboard/up-sales/prospecting/AutoSearchPanel.vue';

const BRAZILIAN_STATES = [
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
];

const MAX_DESIRED_COUNT = 60;

const { t } = useI18n();

const activeTab = ref('manual');


const businessType = ref('');
const neighborhood = ref('');
const city = ref('');
const state = ref(null);
const desiredCount = ref(20);
const minRating = ref('');
const minReviews = ref('');
const requirePhone = ref('yes');
const requireWebsite = ref('no');
const excludeKeywords = ref('');
const notes = ref('');

const isSearching = ref(false);
const isSaving = ref(false);
const results = ref([]);
const selectedIds = ref(new Set());
const hasSearched = ref(false);

const stateOptions = BRAZILIAN_STATES.map(uf => ({ value: uf, label: uf }));
const yesNoOptions = computed(() => [
  { value: 'yes', label: t('CRM.PROSPECTING.FORM.YES') },
  { value: 'no', label: t('CRM.PROSPECTING.FORM.NO') },
]);

const selectedCount = computed(() => selectedIds.value.size);
const canAddLeads = computed(() => selectedCount.value > 0);
const canSearch = computed(
  () => businessType.value.trim() && city.value.trim() && state.value
);

// O botao desabilitado sozinho nao diz o que falta -- parece que travou. Isso nomeia os campos
// que faltam, na mesma ordem em que aparecem no formulario.
const missingRequiredFields = computed(() => {
  const missing = [];
  if (!businessType.value.trim()) {
    missing.push(t('CRM.PROSPECTING.FORM.BUSINESS_TYPE_LABEL'));
  }
  if (!city.value.trim()) missing.push(t('CRM.PROSPECTING.FORM.CITY_LABEL'));
  if (!state.value) missing.push(t('CRM.PROSPECTING.FORM.STATE_LABEL'));
  return missing;
});

const toggleResult = resultId => {
  const next = new Set(selectedIds.value);
  if (next.has(resultId)) {
    next.delete(resultId);
  } else {
    next.add(resultId);
  }
  selectedIds.value = next;
};

const onSearch = async () => {
  if (!canSearch.value) return;

  isSearching.value = true;
  hasSearched.value = true;
  selectedIds.value = new Set();
  try {
    const { data } = await ProspectingAPI.search({
      business_type: businessType.value.trim(),
      neighborhood: neighborhood.value.trim() || undefined,
      city: city.value.trim(),
      state: state.value,
      desired_count: desiredCount.value,
      min_rating: minRating.value || undefined,
      min_reviews: minReviews.value || undefined,
      require_phone: requirePhone.value === 'yes',
      require_website: requireWebsite.value === 'yes',
      exclude_keywords: excludeKeywords.value.trim() || undefined,
      notes: notes.value.trim() || undefined,
    });
    results.value = data.payload || [];
  } catch {
    useAlert(t('CRM.PROSPECTING.SEARCH.ERROR'));
    results.value = [];
  } finally {
    isSearching.value = false;
  }
};

const onAddLeads = async () => {
  isSaving.value = true;
  const requestedCount = selectedCount.value;
  try {
    const { data } = await ProspectingAPI.createLeads({
      resultIds: Array.from(selectedIds.value),
    });
    // The backend skips (and logs) any result that fails to become a valid Contact/Lead instead
    // of failing the whole request, so a 200 here does NOT guarantee every selected lead was
    // created. Match by place_id (the lead's additional_attributes carries it) so only the
    // results that actually succeeded disappear from the list -- the rest stay selected.
    const createdPlaceIds = new Set(
      (data.payload || []).map(lead => lead.additional_attributes?.place_id)
    );
    const createdCount = createdPlaceIds.size;

    if (createdCount === 0) {
      useAlert(t('CRM.PROSPECTING.CREATE.ERROR'));
    } else if (createdCount < requestedCount) {
      useAlert(
        t('CRM.PROSPECTING.CREATE.PARTIAL_SUCCESS', {
          created: createdCount,
          total: requestedCount,
        })
      );
    } else {
      useAlert(t('CRM.PROSPECTING.CREATE.SUCCESS', { n: createdCount }));
    }

    selectedIds.value = new Set(
      Array.from(selectedIds.value).filter(
        id =>
          !createdPlaceIds.has(results.value.find(r => r.id === id)?.place_id)
      )
    );
    results.value = results.value.filter(
      result => !createdPlaceIds.has(result.place_id)
    );
  } catch {
    useAlert(t('CRM.PROSPECTING.CREATE.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

</script>

<template>
  <div class="flex flex-col h-full min-h-0 overflow-y-auto p-6 gap-6">
    <h1 class="text-xl font-semibold text-n-slate-12">
      {{ t('CRM.PROSPECTING.TITLE') }}
    </h1>

    <div class="flex gap-1 border-b border-n-weak">
      <button
        type="button"
        class="px-3 py-2 text-sm font-medium border-b-2 -mb-px"
        :class="
          activeTab === 'manual'
            ? 'border-n-brand text-n-slate-12'
            : 'border-transparent text-n-slate-11'
        "
        @click="activeTab = 'manual'"
      >
        {{ t('CRM.PROSPECTING.TABS.MANUAL') }}
      </button>
      <button
        type="button"
        class="px-3 py-2 text-sm font-medium border-b-2 -mb-px"
        :class="
          activeTab === 'auto'
            ? 'border-n-brand text-n-slate-12'
            : 'border-transparent text-n-slate-11'
        "
        @click="activeTab = 'auto'"
      >
        {{ t('CRM.PROSPECTING.TABS.AUTO') }}
      </button>
    </div>

    <AutoSearchPanel v-if="activeTab === 'auto'" />

    <form
      v-if="activeTab === 'manual'"
      class="flex flex-col gap-4 max-w-3xl"
      @submit.prevent="onSearch"
    >
      <Input
        v-model="businessType"
        :label="t('CRM.PROSPECTING.FORM.BUSINESS_TYPE_LABEL')"
        :placeholder="t('CRM.PROSPECTING.FORM.BUSINESS_TYPE_PLACEHOLDER')"
      />

      <div class="grid grid-cols-3 gap-3">
        <Input
          v-model="neighborhood"
          :label="t('CRM.PROSPECTING.FORM.NEIGHBORHOOD_LABEL')"
          :placeholder="t('CRM.PROSPECTING.FORM.NEIGHBORHOOD_PLACEHOLDER')"
        />
        <Input
          v-model="city"
          :label="t('CRM.PROSPECTING.FORM.CITY_LABEL')"
          :placeholder="t('CRM.PROSPECTING.FORM.CITY_PLACEHOLDER')"
        />
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.PROSPECTING.FORM.STATE_LABEL') }}
          </label>
          <ComboBox
            :model-value="state"
            :options="stateOptions"
            :placeholder="t('CRM.PROSPECTING.FORM.STATE_PLACEHOLDER')"
            @update:model-value="value => (state = value)"
          />
        </div>
      </div>

      <div class="grid grid-cols-3 gap-3 items-start">
        <div class="flex flex-col gap-1">
          <Input
            v-model.number="desiredCount"
            type="number"
            min="1"
            :max="MAX_DESIRED_COUNT"
            :label="t('CRM.PROSPECTING.FORM.DESIRED_COUNT_LABEL')"
          />
          <span class="text-xs text-n-slate-11">
            {{ t('CRM.PROSPECTING.FORM.DESIRED_COUNT_HELP') }}
          </span>
        </div>
        <Input
          v-model="minRating"
          type="number"
          step="0.1"
          min="0"
          max="5"
          :label="t('CRM.PROSPECTING.FORM.MIN_RATING_LABEL')"
          :placeholder="t('CRM.PROSPECTING.FORM.MIN_RATING_PLACEHOLDER')"
        />
        <Input
          v-model="minReviews"
          type="number"
          min="0"
          :label="t('CRM.PROSPECTING.FORM.MIN_REVIEWS_LABEL')"
          :placeholder="t('CRM.PROSPECTING.FORM.MIN_REVIEWS_PLACEHOLDER')"
        />
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.PROSPECTING.FORM.REQUIRE_PHONE_LABEL') }}
          </label>
          <ComboBox
            :model-value="requirePhone"
            :options="yesNoOptions"
            @update:model-value="value => (requirePhone = value)"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.PROSPECTING.FORM.REQUIRE_WEBSITE_LABEL') }}
          </label>
          <ComboBox
            :model-value="requireWebsite"
            :options="yesNoOptions"
            @update:model-value="value => (requireWebsite = value)"
          />
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.PROSPECTING.FORM.EXCLUDE_KEYWORDS_LABEL') }}
          </label>
          <textarea
            v-model="excludeKeywords"
            rows="2"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            :placeholder="
              t('CRM.PROSPECTING.FORM.EXCLUDE_KEYWORDS_PLACEHOLDER')
            "
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.PROSPECTING.FORM.NOTES_LABEL') }}
          </label>
          <textarea
            v-model="notes"
            rows="2"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            :placeholder="t('CRM.PROSPECTING.FORM.NOTES_PLACEHOLDER')"
          />
        </div>
      </div>

      <div class="flex items-center justify-end gap-3">
        <span
          v-if="missingRequiredFields.length"
          class="text-xs text-n-slate-11"
        >
          {{
            t('CRM.PROSPECTING.FORM.REQUIRED_HINT', {
              fields: missingRequiredFields.join(', '),
            })
          }}
        </span>
        <Button
          type="submit"
          :label="t('CRM.PROSPECTING.FORM.SUBMIT')"
          :is-loading="isSearching"
          :disabled="!canSearch"
        />
      </div>
    </form>

    <div
      v-if="activeTab === 'manual' && hasSearched && !isSearching"
      class="flex flex-col gap-4"
    >
      <div v-if="results.length === 0" class="text-sm text-n-slate-11">
        {{ t('CRM.PROSPECTING.SEARCH.EMPTY') }}
      </div>

      <template v-else>
        <div class="flex items-center gap-3 flex-wrap">
          <Button
            :label="t('CRM.PROSPECTING.CREATE.ACTION', { n: selectedCount })"
            :disabled="!canAddLeads"
            :is-loading="isSaving"
            @click="onAddLeads"
          />
        </div>

        <div class="flex flex-col gap-2">
          <label
            v-for="result in results"
            :key="result.id"
            class="flex items-start gap-3 p-3 rounded-lg border border-n-weak bg-n-solid-1 cursor-pointer"
          >
            <input
              type="checkbox"
              class="mt-1"
              :checked="selectedIds.has(result.id)"
              @change="toggleResult(result.id)"
            />
            <div class="flex flex-col min-w-0">
              <span class="text-sm font-medium text-n-slate-12">
                {{ result.name }}
              </span>
              <span class="text-xs text-n-slate-11">{{ result.address }}</span>
              <span v-if="result.phone_number" class="text-xs text-n-slate-11">
                {{ result.phone_number }}
              </span>
              <span v-if="result.rating" class="text-xs text-n-slate-11">
                {{
                  t('CRM.PROSPECTING.RESULT.RATING', {
                    rating: result.rating,
                    count: result.user_ratings_total || 0,
                  })
                }}
              </span>
            </div>
          </label>
        </div>
      </template>
    </div>
  </div>
</template>

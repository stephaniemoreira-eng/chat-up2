import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import CrmIndex from './pages/CrmIndex.vue';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.SALES_PIPELINE,
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/crm'),
    component: CrmIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'crm_pipeline_index',
        component: CrmIndex,
        meta: commonMeta,
      },
      {
        path: ':pipelineId',
        name: 'crm_pipeline_show',
        component: CrmIndex,
        meta: commonMeta,
        props: true,
      },
    ],
  },
];

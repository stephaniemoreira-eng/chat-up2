import { frontendURL } from '../../../helper/URLHelper';
import SettingsWrapper from '../settings/SettingsWrapper.vue';
import BrandingIndex from './branding/Index.vue';
import DashboardIndex from './dashboard/Index.vue';
import ProspectingIndex from './prospecting/Index.vue';
import FollowUpIndex from './follow-up/Index.vue';

// Rotas aditivas do Up Sales — reskin dentro do chat-up2. Ver
// docs/fork/ADR-0004-up-sales-reskin.md. Cada nova tela (Dashboard, Busca, Super Admin,
// Calculadora, Agenda) entra aqui como uma rota nova, sem tocar em rota nativa.
export const routes = [
  {
    path: frontendURL('accounts/:accountId/up-sales/dashboard'),
    name: 'up_sales_dashboard_index',
    component: DashboardIndex,
    meta: { permissions: ['administrator', 'agent'] },
  },
  {
    path: frontendURL('accounts/:accountId/up-sales/prospecting'),
    name: 'up_sales_prospecting_index',
    component: ProspectingIndex,
    meta: { permissions: ['administrator', 'agent'] },
  },
  {
    path: frontendURL('accounts/:accountId/up-sales/follow-up'),
    name: 'up_sales_follow_up_index',
    component: FollowUpIndex,
    meta: { permissions: ['administrator'] },
  },
  {
    path: frontendURL('accounts/:accountId/settings/up-sales-branding'),
    meta: { permissions: ['administrator'] },
    component: SettingsWrapper,
    children: [
      {
        path: '',
        name: 'up_sales_branding_index',
        component: BrandingIndex,
        meta: { permissions: ['administrator'] },
      },
    ],
  },
];

import { mount } from '@vue/test-utils';
import CommercialActionsPanel from './CommercialActionsPanel.vue';

// Achado testando ao vivo em teste. (22/09): `color="green"` no botão Marcar Ganho não é um dos
// tokens que o Button (`next/button/constants.js`, COLOR_OPTIONS) aceita -- `STYLE_CONFIG.colors`
// não tem chave `green`, então o computed de variantClasses quebra em runtime (`Cannot read
// properties of undefined (reading 'ghost')`) e o botão inteiro some da tela, sem erro nenhum na
// CI, porque nenhum spec desta pasta faz mount de verdade do Button real. `shallowMount` não
// serviria aqui -- ele troca o Button por um stub e nunca executa o computed que quebrou.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('CommercialActionsPanel', () => {
  it('renderiza os botões de ação (propensão, callback, no-show, ganho/perdido) sem quebrar', () => {
    const wrapper = mount(CommercialActionsPanel, {
      props: { engineTags: ['callback'], engineStageKey: 'oportunidade', isSaving: false },
    });

    const labels = wrapper.findAll('button').map(button => button.text());

    expect(labels).toContain('CRM.LEAD.DETAIL.COMMERCIAL.MARK_WON');
    expect(labels).toContain('CRM.LEAD.DETAIL.COMMERCIAL.MARK_LOST');
    expect(labels).toContain('CRM.LEAD.DETAIL.COMMERCIAL.CALLBACK_REALIZADO');
    expect(labels).toContain('CRM.LEAD.DETAIL.COMMERCIAL.NO_SHOW');
  });

  it('esconde as ações e mostra o texto de resolução quando já é ganho/perdido', () => {
    const wrapper = mount(CommercialActionsPanel, {
      props: { engineTags: [], engineStageKey: 'ganho', isSaving: false },
    });

    expect(wrapper.text()).toContain('CRM.LEAD.DETAIL.COMMERCIAL.RESOLVED_WON');
    expect(wrapper.findAll('button')).toHaveLength(0);
  });
});

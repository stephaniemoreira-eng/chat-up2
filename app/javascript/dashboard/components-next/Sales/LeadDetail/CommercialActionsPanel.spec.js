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
  const labelsFor = props =>
    mount(CommercialActionsPanel, { props: { isSaving: false, ...props } })
      .findAll('button')
      .map(button => button.text());

  it('renderiza os botões de ação (propensão, callback, no-show, ganho/perdido) sem quebrar', () => {
    const labels = labelsFor({
      engineTags: ['callback'],
      engineStageKey: 'em_acompanhamento',
    });

    expect(labels).toContain('CRM.LEAD.DETAIL.COMMERCIAL.MARK_WON');
    expect(labels).toContain('CRM.LEAD.DETAIL.COMMERCIAL.MARK_LOST');
    expect(labels).toContain('CRM.LEAD.DETAIL.COMMERCIAL.CALLBACK_REALIZADO');
    expect(labels).toContain('CRM.LEAD.DETAIL.COMMERCIAL.NO_SHOW');
  });

  // CP-05 (P1-025-02, §8.4): Ganho/Perdido só a partir de Em acompanhamento -- em Oportunidade o
  // painel oferece a movimentação Comercial (ação do Engine) no lugar.
  it('em Oportunidade oferece mover para Em acompanhamento e esconde Ganho/Perdido', () => {
    const labels = labelsFor({
      engineTags: [],
      engineStageKey: 'oportunidade',
    });

    expect(labels).toContain('CRM.LEAD.DETAIL.COMMERCIAL.START_ACOMPANHAMENTO');
    expect(labels).not.toContain('CRM.LEAD.DETAIL.COMMERCIAL.MARK_WON');
    expect(labels).not.toContain('CRM.LEAD.DETAIL.COMMERCIAL.MARK_LOST');
  });

  it('emite advance-etapa-comercial com em_acompanhamento', async () => {
    const wrapper = mount(CommercialActionsPanel, {
      props: {
        engineTags: [],
        engineStageKey: 'oportunidade',
        isSaving: false,
      },
    });
    const button = wrapper
      .findAll('button')
      .find(
        b => b.text() === 'CRM.LEAD.DETAIL.COMMERCIAL.START_ACOMPANHAMENTO'
      );

    await button.trigger('click');

    expect(wrapper.emitted('advance-etapa-comercial')).toEqual([
      ['em_acompanhamento'],
    ]);
  });

  // CP-05 (P2-025-03, §20.3): remoção manual da tag NO-SHOW só quando ela está presente.
  it('mostra Remover NO-SHOW apenas quando a tag no_show está no card', () => {
    expect(
      labelsFor({
        engineTags: ['no_show'],
        engineStageKey: 'em_acompanhamento',
      })
    ).toContain('CRM.LEAD.DETAIL.COMMERCIAL.REMOVE_NO_SHOW');
    expect(
      labelsFor({ engineTags: [], engineStageKey: 'em_acompanhamento' })
    ).not.toContain('CRM.LEAD.DETAIL.COMMERCIAL.REMOVE_NO_SHOW');
  });

  it('esconde as ações e mostra o texto de resolução quando já é ganho/perdido', () => {
    const wrapper = mount(CommercialActionsPanel, {
      props: { engineTags: [], engineStageKey: 'ganho', isSaving: false },
    });

    expect(wrapper.text()).toContain('CRM.LEAD.DETAIL.COMMERCIAL.RESOLVED_WON');
    expect(wrapper.findAll('button')).toHaveLength(0);
  });
});

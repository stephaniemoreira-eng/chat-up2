// Paleta oficial UP2 -- Manual de Marca v1.0, pag. 13. Duas regras do manual governam este
// arquivo: Copper Vermilion (#D95B3D) e' "intervencao" -- aparece so no dado que exige decisao,
// com proporcao recomendada de 4% -- e, em leitura de dados, "nunca colorir todas as barras: o
// Copper indica o dado que exige decisao". Por isso a faixa de revisao prioritaria e o pilar mais
// fraco recebem Copper, e todo o resto fica em tons neutros.
//
// Compartilhado entre ScanPanel.vue (detalhe do lead) e LeadCard.vue (card do Kanban) para as
// tres faixas nao sairem de sincronia -- elas espelham ScanWeights::FAIXAS no backend.

export const SCAN_FAIXA_CLASSES = {
  baixa_prioridade: 'bg-n-slate-3 text-n-slate-11',
  revisao_humana: 'bg-n-amber-3 text-n-amber-11',
  revisao_prioritaria:
    'bg-[#D95B3D]/12 text-[#A8401F] dark:bg-[#D95B3D]/20 dark:text-[#E88A6F]',
};

export const SCAN_FAIXA_FALLBACK_CLASS = 'bg-n-slate-3 text-n-slate-11';

export const scanFaixaClass = faixa =>
  SCAN_FAIXA_CLASSES[faixa] || SCAN_FAIXA_FALLBACK_CLASS;

// Barra do pilar: neutra por padrao, Copper apenas no pilar que puxa o score para baixo.
export const SCAN_PILAR_BAR_CLASS = 'bg-n-slate-9';
export const SCAN_PILAR_BAR_ATTENTION_CLASS = 'bg-[#D95B3D]';

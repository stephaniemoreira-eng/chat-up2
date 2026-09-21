// Tags computadas pelo Operational Engine (§20.1 do SSOT), refletidas em
// custom_attributes.engine_tags -- ver enterprise/app/services/operational_engine/
// sales_projection_sync.rb. Mesma paleta oficial UP2 usada em scanVisuals.js: neutro por
// padrão, Copper Vermilion só no que exige ação de alguém (aqui, um callback pendente).

export const ENGINE_TAG_CLASSES = {
  lavinia: 'bg-n-slate-3 text-n-slate-11',
  // Reaproveita a mesma classe de "revisão humana" do Scan -- mesma ideia: uma pessoa,
  // não o agente, está com isto agora.
  humano: 'bg-n-amber-3 text-n-amber-11',
  callback:
    'bg-[#D95B3D]/12 text-[#A8401F] dark:bg-[#D95B3D]/20 dark:text-[#E88A6F]',
};

export const ENGINE_TAG_FALLBACK_CLASS = 'bg-n-slate-3 text-n-slate-11';

export const engineTagClass = tag =>
  ENGINE_TAG_CLASSES[tag] || ENGINE_TAG_FALLBACK_CLASS;

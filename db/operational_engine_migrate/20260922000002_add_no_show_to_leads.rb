# §20.3: NO-SHOW é uma exceção transversal, não uma etapa. Timestamp (não boolean) segue o
# mesmo padrão de agendado_em/callback_realizado_em -- guarda QUANDO o fato aconteceu, e dá pra
# "tratar/remarcar" limpando de volta pra NULL sem perder o registro histórico, porque o evento
# em si (lead_events, append-only) permanece para sempre -- só o campo que controla a tag visual
# atual é que pode voltar a NULL.
class AddNoShowToLeads < OperationalEngine::Migration
  def up
    add_column :leads, :no_show_em, :timestamptz
  end

  def down
    remove_column :leads, :no_show_em
  end
end

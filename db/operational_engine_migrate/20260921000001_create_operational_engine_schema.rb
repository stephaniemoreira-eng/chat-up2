# Runs against the Supabase connection (OPERATIONAL_ENGINE_DATABASE_URL) via `rake oe:migrate`,
# never against the primary Chatwoot database. Lives outside db/migrate/ on purpose: a normal
# `rails db:migrate` must never touch this, and db:schema:dump must never see it (see
# OperationalEngine::Record and the fork's `schema-consistency` CI job).
#
# Field list, enums and write-once/append-only rules are normative: SSOT MVP01 v1.0 §6 (leads)
# and §7 (lead_events). Enums are TEXT + CHECK, not native Postgres enum types, so a future value
# is one migration away instead of a type change. Fields with no closed list in §6.2
# (origem_lead, modo_entrada is the exception -- see below, tipo_entrada, relacao_atual,
# motivo_perda) stay plain TEXT: inventing a closed list for them would be a business-rule
# decision this migration has no authority to make (§32).
#
# `conta_id` is NOT in the SSOT §6.1 field list: the SSOT assumed one Supabase project per
# client. Decisão de 20/09/2026: este projeto é compartilhado por todos os clientes Up Sales,
# não só a Lava e Pronto, então o isolamento por tenant precisa existir no schema desde já --
# sem FK real (Supabase não enxerga o Postgres do Chatwoot), mesmo padrão de
# inbox_entrada_id/upsales_contact_id.
class CreateOperationalEngineSchema < OperationalEngine::Migration
  def up
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    create_table :leads, id: false do |t|
      t.uuid :lead_id, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.bigint :conta_id, null: false
      t.text :telefone, null: false
      t.text :nome
      t.text :empresa
      t.text :email

      t.text :origem_lead
      t.text :modo_entrada
      t.text :tipo_entrada
      t.text :relacao_atual

      t.bigint :inbox_entrada_id
      t.bigint :inbox_atual_id
      t.jsonb :dados_origem, null: false, default: {}

      t.text :etapa_prospect, null: false, default: 'backlog'
      t.timestamptz :etapa_entrou_em
      t.text :lead_status, null: false, default: 'ativo'
      t.text :qualificacao_status, null: false, default: 'em_qualificacao'
      t.text :recuperacao_status, null: false, default: 'inativa'
      t.integer :tentativa_recuperacao, null: false, default: 0
      t.timestamptz :proxima_recuperacao_em
      t.boolean :aguardando_resposta, null: false, default: false
      t.text :ultimo_ponto

      t.text :agendamento_status, null: false, default: 'nao_iniciado'
      t.text :orcamento_status, null: false, default: 'nao_solicitado'
      t.text :resultado_comercial, null: false, default: 'em_aberto'

      t.text :modo_atendimento, null: false, default: 'lavinia'
      t.timestamptz :modo_atendimento_entrou_em
      t.bigint :responsavel_atual_id

      t.text :frente_operacional, null: false, default: 'prospeccao'
      t.text :etapa_comercial
      t.boolean :nao_contatar, null: false, default: false
      t.text :propensao_fechamento, null: false, default: 'nao_classificado'

      t.text :segmento
      t.text :modelo_atual
      t.text :dor_oportunidade
      t.text :impacto
      t.text :intencao_comercial
      t.text :resumo_oportunidade

      t.text :regiao
      t.text :cep
      t.text :cobertura_status
      t.numeric :volume_mensal_kg
      t.integer :retiradas_semana

      t.text :motivo_handoff
      t.text :motivo_perda
      t.text :motivo_encerramento

      t.text :calendar_event_id

      t.timestamptz :entrada_operacao_em
      t.timestamptz :primeiro_contato_em
      t.timestamptz :primeira_resposta_em
      t.timestamptz :ultima_interacao_em
      t.timestamptz :qualificado_em
      t.timestamptz :agendado_em
      t.timestamptz :callback_realizado_em
      t.timestamptz :conversao_em
      t.text :tipo_conversao
      t.timestamptz :ganho_em

      # Técnicos, não conceituais (§6.1) -- referência de volta ao domínio nativo do Chatwoot,
      # nunca fonte de estado de negócio.
      t.bigint :upsales_contact_id
      t.bigint :upsales_conversation_atual_id

      t.timestamptz :criado_em, null: false, default: -> { 'now()' }
      t.timestamptz :atualizado_em, null: false, default: -> { 'now()' }
    end

    add_index :leads, %i[conta_id telefone], unique: true
    add_index :leads, :conta_id
    add_index :leads, :entrada_operacao_em
    add_index :leads, %i[lead_status etapa_prospect]
    add_index :leads, :proxima_recuperacao_em,
              where: "lead_status = 'ativo' AND recuperacao_status = 'ativa'",
              name: 'index_leads_on_proxima_recuperacao_em_when_active'
    add_index :leads, :modo_entrada
    add_index :leads, :origem_lead
    add_index :leads, :segmento
    add_index :leads, :inbox_entrada_id
    add_index :leads, :inbox_atual_id
    add_index :leads, :conversao_em
    add_index :leads, :responsavel_atual_id

    execute <<~SQL
      ALTER TABLE leads ADD CONSTRAINT chk_leads_modo_entrada
        CHECK (modo_entrada IS NULL OR modo_entrada IN ('inbound', 'outbound'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_etapa_prospect
        CHECK (etapa_prospect IN ('backlog', 'contatado', 'em_conversa', 'qualificado', 'agendado'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_lead_status
        CHECK (lead_status IN ('ativo', 'encerrado'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_qualificacao_status
        CHECK (qualificacao_status IN ('em_qualificacao', 'qualificado', 'nao_qualificado', 'nao_concluido'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_recuperacao_status
        CHECK (recuperacao_status IN ('inativa', 'ativa'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_agendamento_status
        CHECK (agendamento_status IN ('nao_iniciado', 'em_andamento', 'confirmado', 'callback_registrado', 'callback_realizado', 'cancelado'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_orcamento_status
        CHECK (orcamento_status IN ('nao_solicitado', 'em_dimensionamento', 'informado', 'personalizado'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_resultado_comercial
        CHECK (resultado_comercial IN ('em_aberto', 'ganho', 'perdido'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_modo_atendimento
        CHECK (modo_atendimento IN ('lavinia', 'humano'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_frente_operacional
        CHECK (frente_operacional IN ('prospeccao', 'comercial'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_etapa_comercial
        CHECK (etapa_comercial IS NULL OR etapa_comercial IN ('oportunidade', 'em_acompanhamento', 'ganho', 'perdido'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_propensao_fechamento
        CHECK (propensao_fechamento IN ('nao_classificado', 'frio', 'morno', 'quente'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_intencao_comercial
        CHECK (intencao_comercial IS NULL OR intencao_comercial IN ('informativo', 'avaliando', 'quer_orcamento', 'quer_avancar'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_cobertura_status
        CHECK (cobertura_status IS NULL OR cobertura_status IN ('atendida', 'fora_cobertura', 'a_validar', 'nao_identificada'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_tipo_conversao
        CHECK (tipo_conversao IS NULL OR tipo_conversao IN ('agendamento', 'callback'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_motivo_handoff
        CHECK (motivo_handoff IS NULL OR motivo_handoff IN ('avanco_comercial', 'orcamento_personalizado', 'excecao'));

      ALTER TABLE leads ADD CONSTRAINT chk_leads_motivo_encerramento
        CHECK (motivo_encerramento IS NULL OR motivo_encerramento IN ('sem_resposta', 'sem_interesse', 'nao_qualificado', 'cliente_atual', 'nao_contatar', 'fora_escopo', 'outro'));
    SQL

    create_table :lead_events, id: false do |t|
      t.uuid :event_id, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.uuid :lead_id, null: false
      t.text :event_type, null: false
      t.timestamptz :event_at, null: false, default: -> { 'now()' }
      t.text :source, null: false
      t.jsonb :metadata, null: false, default: {}
    end

    add_foreign_key :lead_events, :leads, column: :lead_id, primary_key: :lead_id
    add_index :lead_events, :lead_id
    add_index :lead_events, :event_type
    add_index :lead_events, :event_at

    execute <<~SQL
      ALTER TABLE lead_events ADD CONSTRAINT chk_lead_events_source
        CHECK (source IN ('system', 'lavinia', 'human', 'commercial', 'import'));
    SQL

    # §7.2: append-only. A real correction is a new row, not an edit of history.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION lead_events_block_mutation() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'lead_events is append-only: % is not allowed', TG_OP;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER lead_events_no_update
        BEFORE UPDATE ON lead_events
        FOR EACH ROW EXECUTE FUNCTION lead_events_block_mutation();

      CREATE TRIGGER lead_events_no_delete
        BEFORE DELETE ON lead_events
        FOR EACH ROW EXECUTE FUNCTION lead_events_block_mutation();
    SQL

    # §6.3: fields that, once set from a real fact, must not be silently rewritten. A caller
    # that genuinely needs to change one of these has a data problem to resolve by hand, not a
    # code path -- so this fails loudly instead of reverting quietly.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION leads_block_write_once() RETURNS trigger AS $$
      BEGIN
        IF OLD.origem_lead IS NOT NULL AND NEW.origem_lead IS DISTINCT FROM OLD.origem_lead THEN
          RAISE EXCEPTION 'leads.origem_lead is write-once and already set';
        END IF;
        IF OLD.inbox_entrada_id IS NOT NULL AND NEW.inbox_entrada_id IS DISTINCT FROM OLD.inbox_entrada_id THEN
          RAISE EXCEPTION 'leads.inbox_entrada_id is write-once and already set';
        END IF;
        IF OLD.entrada_operacao_em IS NOT NULL AND NEW.entrada_operacao_em IS DISTINCT FROM OLD.entrada_operacao_em THEN
          RAISE EXCEPTION 'leads.entrada_operacao_em is write-once and already set';
        END IF;
        IF OLD.conversao_em IS NOT NULL AND NEW.conversao_em IS DISTINCT FROM OLD.conversao_em THEN
          RAISE EXCEPTION 'leads.conversao_em is write-once and already set';
        END IF;
        IF OLD.conversao_em IS NOT NULL AND NEW.tipo_conversao IS DISTINCT FROM OLD.tipo_conversao THEN
          RAISE EXCEPTION 'leads.tipo_conversao is locked once conversao_em is set';
        END IF;

        NEW.atualizado_em := now();
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER leads_write_once_and_touch
        BEFORE UPDATE ON leads
        FOR EACH ROW EXECUTE FUNCTION leads_block_write_once();
    SQL
  end

  def down
    drop_table :lead_events
    execute 'DROP FUNCTION IF EXISTS lead_events_block_mutation()'
    execute 'DROP FUNCTION IF EXISTS leads_block_write_once()'
    drop_table :leads
  end
end

require 'rails_helper'

RSpec.describe OperationalEngine::SalesProjectionSync do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def build_lead(**overrides)
    OperationalEngine::Lead.create!({
      conta_id: account.id, telefone: "+551399#{rand(1_000_000..9_999_999)}", upsales_contact_id: contact.id
    }.merge(overrides))
  end

  it 'nao faz nada quando o lead nao tem upsales_contact_id ainda' do
    lead = build_lead(upsales_contact_id: nil)

    expect(described_class.call(lead)).to be_nil
    expect(Sales::Lead.count).to eq(0)
  end

  it 'cria um Sales::Lead pro contato quando ainda nao existe um' do
    lead = build_lead(empresa: 'Lava e Pronto')

    sales_lead = described_class.call(lead)

    expect(sales_lead).to be_persisted
    expect(sales_lead.account_id).to eq(account.id)
    expect(sales_lead.contact_id).to eq(contact.id)
    expect(sales_lead.title).to eq('Lava e Pronto')
  end

  it 'atualiza o Sales::Lead existente em vez de duplicar' do
    lead = build_lead(empresa: 'Nome Antigo')
    described_class.call(lead)

    lead.update!(empresa: 'Nome Novo')
    described_class.call(lead)

    expect(Sales::Lead.where(contact_id: contact.id).count).to eq(1)
    expect(Sales::Lead.find_by(contact_id: contact.id).title).to eq('Nome Novo')
  end

  it 'usa o nome quando nao ha empresa, e o telefone como ultimo recurso' do
    lead = build_lead(empresa: nil, nome: 'Fulano')
    expect(described_class.call(lead).title).to eq('Fulano')

    other_contact = create(:contact, account: account)
    lead_sem_nome = build_lead(empresa: nil, nome: nil, upsales_contact_id: other_contact.id)
    expect(described_class.call(lead_sem_nome).title).to eq(lead_sem_nome.telefone)
  end
end

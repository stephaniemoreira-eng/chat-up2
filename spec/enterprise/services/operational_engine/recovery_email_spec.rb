require 'rails_helper'

# CP-16A -- P2-VAL-17 (decisão da Stéphanie em 24/09/2026: texto do e-mail da 3ª tentativa de recovery
# "SER AJUSTÁVEL", por conta).
RSpec.describe OperationalEngine::RecoveryEmail do
  let(:account) { create(:account, name: 'Lava e Pronto') }
  let(:lead) do
    OperationalEngine::Lead.create!(conta_id: account.id, telefone: '+5513991239876', nome: 'Ana', empresa: 'Hotel Mar')
  end

  around do |example|
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    example.run
  ensure
    ActionMailer::Base.delivery_method = original
  end

  it 'usa o assunto e o corpo configurados na conta' do
    create(:up_sales_agent_tenant, account: account, recovery_email_subject: '{{nome}}, novidades da {{marca}}',
                                   recovery_email_body: 'Oi {{nome}} da {{empresa}}, aqui é a {{persona}}.')

    described_class.deliver!(lead: lead, address: 'compras@hotel.example.com', account: account)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.subject).to eq('Ana, novidades da Lava e Pronto')
    expect(mail.body.decoded.dup.force_encoding(Encoding::UTF_8)).to include('Oi Ana da Hotel Mar, aqui é a Lavínia.')
  end

  it 'sem configuração na conta mantém o modelo neutro do CP-13' do
    described_class.deliver!(lead: lead, address: 'compras@hotel.example.com', account: account)

    expect(ActionMailer::Base.deliveries.last.subject).to eq('Lava e Pronto: podemos continuar nossa conversa?')
  end

  it 'mascara o endereço na mensagem de falha (nunca vai para log/registro de falha)' do
    allow(OperationalEngine::RecoveryMailer).to receive(:with).and_raise(RuntimeError, '550 <compras@hotel.example.com> unknown')

    expect { described_class.deliver!(lead: lead, address: 'compras@hotel.example.com', account: account) }
      .to raise_error(described_class::DeliveryError) { |e| expect(e.message).not_to include('compras@hotel.example.com') }
  end
end

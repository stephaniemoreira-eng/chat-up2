require 'rails_helper'

# CP-13 (modelo neutro) + CP-16A -- P2-VAL-17 (decisão da Stéphanie em 24/09/2026: o texto do e-mail
# da 3ª tentativa de recovery deve "SER AJUSTÁVEL", por conta, com placeholders seguros).
RSpec.describe OperationalEngine::RecoveryMailer do
  def build_mail(**params)
    described_class.with({ to: 'compras@hotel.example.com', nome: 'Ana', empresa: 'Hotel Mar', marca: 'Lava e Pronto' }.merge(params))
                   .follow_up
  end

  def text(mail)
    mail.body.decoded.dup.force_encoding(Encoding::UTF_8)
  end

  it 'sem texto configurado usa o modelo neutro padrão' do
    mail = build_mail

    expect(mail.subject).to eq('Lava e Pronto: podemos continuar nossa conversa?')
    expect(text(mail)).to include('Olá, Ana!')
    expect(text(mail)).to include('Aqui é a Lavínia, da Lava e Pronto.')
  end

  it 'usa o assunto e o corpo configurados, substituindo os placeholders' do
    mail = build_mail(subject_template: '{{nome}}, a {{marca}} quer falar com a {{empresa}}',
                      body_template: "Oi {{ nome }}!\r\nSou a {{persona}}.")

    expect(mail.subject).to eq('Ana, a Lava e Pronto quer falar com a Hotel Mar')
    expect(text(mail)).to include('Oi Ana!')
    expect(text(mail)).to include('Sou a Lavínia.')
  end

  it 'texto configurado só com espaços cai no modelo padrão' do
    expect(build_mail(subject_template: '   ', body_template: "\n").subject).to eq('Lava e Pronto: podemos continuar nossa conversa?')
  end

  it 'valores com quebra de linha não injetam cabeçalho nem parágrafos; nada é avaliado' do
    mail = build_mail(nome: "Ana\r\nBcc: x@evil.example.com", subject_template: 'Oi {{nome}}', body_template: 'Oi {{nome}} {{nome.upcase}} <%= 2 %>')

    expect(mail.subject).to eq('Oi Ana Bcc: x@evil.example.com')
    expect(mail.bcc).to be_nil
    expect(text(mail)).to include('Oi Ana Bcc: x@evil.example.com {{nome.upcase}} <%= 2 %>')
  end

  it 'placeholder desconhecido ou valor ausente vira texto vazio' do
    mail = build_mail(empresa: nil, body_template: 'Empresa: [{{empresa}}] [{{email}}]')

    expect(text(mail)).to include('Empresa: [] []')
  end
end

require 'rails_helper'

RSpec.describe Conversations::Anonymizer do
  subject(:anonymizer) { described_class.new(['Juan Pérez', 'Ana']) }

  it 'replaces full names and long name parts, ignoring case' do
    expect(anonymizer.call('Hola juan pérez, soy PÉREZ. Ana no.')).to eq('Hola [NOMBRE], soy [NOMBRE]. Ana no.')
  end

  it 'collapses adjacent name placeholders' do
    expect(described_class.new(['María José Vera']).call('Hola María José')).to eq('Hola [NOMBRE]')
  end

  it 'replaces RUC, cédula, phone, email, card and URL' do
    text = 'RUC 1790012345001 cédula 1712345678 tel +593 99 123 4567 mail a.b+c@mail.com ' \
           'tarjeta 4111 1111 1111 1111 ver https://example.com/x?y=1 ok'

    expect(anonymizer.call(text)).to eq('RUC [RUC] cédula [CEDULA] tel [TELEFONO] mail [EMAIL] tarjeta [TARJETA] ver [URL] ok')
  end

  it 'collapses whitespace and handles nil' do
    expect(anonymizer.call("  hola \n  mundo ")).to eq('hola mundo')
    expect(anonymizer.call(nil)).to eq('')
  end
end

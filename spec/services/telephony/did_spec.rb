require 'rails_helper'

# Misma tabla que telephony-controller/test/dids.test.ts: las dos capas deben decidir igual.
RSpec.describe Telephony::Did do
  {
    ['+59322000000', ''] => '59322000000',
    %w[59322000000 EC] => '59322000000',
    %w[022000000 EC] => '59322000000',
    ['022000000', ''] => '022000000',
    %w[00593987654321 EC] => '593987654321',
    %w[0987654321 EC] => '593987654321',
    ['7001', ''] => '7001'
  }.each do |(did, country), key|
    it "#{did.inspect} with #{country.presence || 'no country'} → #{key}" do
      expect(described_class.key(did, country)).to eq(key)
    end
  end

  # Misma tabla que telephony-controller/test/phone.test.ts (toE164).
  describe '.e164' do
    {
      ['+593987654321', ''] => '+593987654321',
      ['00593987654321', ''] => '+593987654321',
      %w[0987654321 EC] => '+593987654321',
      ['098 765-4321', 'ec'] => '+593987654321',
      %w[022000000 EC] => '+59322000000',
      %w[593987654321 EC] => '+593987654321',
      ['0987654321', ''] => nil,
      %w[12345 EC] => nil,
      %w[abc EC] => nil
    }.each do |(raw, country), e164|
      it "#{raw.inspect} with #{country.presence || 'no country'} → #{e164.inspect}" do
        expect(described_class.e164(raw, country)).to eq(e164)
      end
    end
  end
end

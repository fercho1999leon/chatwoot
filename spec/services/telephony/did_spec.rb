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
end

require 'rails_helper'

RSpec.describe SuperAdmin::AccountFeaturesHelper do
  describe '.feature_display_names' do
    it 'includes friendly labels for the fork-owned settings-backed flags' do
      names = described_class.feature_display_names

      expect(names['sales_scan']).to eq('Up Sales — Pré-Score (SCAN v1)')
      expect(names['sales_pipeline']).to be_present
      expect(names['sales_kanban']).to be_present
    end
  end
end

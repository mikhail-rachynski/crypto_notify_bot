class Exchange < ApplicationRecord
  enum pair: [:btcusd, :btceur, :ethusd, :etheur]
  belongs_to :coin
end

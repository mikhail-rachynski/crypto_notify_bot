class Exchenge < ApplicationRecord
  enum pair: [:btcusd, :btceur, :ethusd, :etheur]
end

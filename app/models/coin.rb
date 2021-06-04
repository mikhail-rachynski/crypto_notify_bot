class Coin < ApplicationRecord
  enum currency: [:btc, :eth, :usd, :eur]
  belongs_to :user
end

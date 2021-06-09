class Coin < ApplicationRecord
  enum currency: [:btc, :eth, :usd, :eur]
  belongs_to :user
  has_and_belongs_to_many :to_currency
end

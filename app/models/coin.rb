class Coin < ApplicationRecord
  currencies = [:btc, :eth, :usd, :eur]
  enum currency: currencies, _suffix: true
  enum to_currency: currencies, _prefix: :currency

  belongs_to :user
  has_one :exchange, dependent: :destroy
end

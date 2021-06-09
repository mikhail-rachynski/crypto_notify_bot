class ToCurrency < ApplicationRecord
  enum currency: [:btc, :eth, :usd, :eur]
  has_and_belongs_to_many :coin
end

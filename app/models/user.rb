class User < ApplicationRecord
  validates :user, uniqueness: true
  has_many :coin
end

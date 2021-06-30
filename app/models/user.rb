class User < ApplicationRecord
  validates :user, uniqueness: true
  has_many :coin, dependent: :destroy
  has_one :editable, dependent: :destroy
end

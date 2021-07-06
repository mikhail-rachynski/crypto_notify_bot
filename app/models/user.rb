class User < ApplicationRecord
  validates :user, uniqueness: true
  has_many :coin, dependent: :destroy
  has_one :editable, dependent: :destroy
  has_one :admin, dependent: :destroy

  def is_admin
    self.admin.is_admin if self.admin
  end

  def upd_editable(status)
    self.editable.update(status: status)
  end
end

class Admin < ApplicationRecord
  belongs_to :user, optional: true
end

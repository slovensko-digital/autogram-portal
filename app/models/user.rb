# == Schema Information
#
# Table name: users
#
#  id                   :bigint           not null, primary key
#  api_token_public_key :string
#  email                :string
#  name                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
class User < ApplicationRecord
  validates :name, presence: true
  has_many :bundles, foreign_key: "user_id", dependent: :destroy
end

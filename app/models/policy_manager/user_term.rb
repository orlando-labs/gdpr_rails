require "aasm"

module PolicyManager
  class UserTerm < ApplicationRecord
    include AASM
    
    belongs_to :user
    belongs_to :term

    validates_uniqueness_of :term_id, :scope => :user_id

    aasm :column => :state do
      state :rejected, :initial => true
      state :accepted

      event :accept do
        transitions from: :rejected, to: :accepted
      end

      event :reject do
        transitions from: :accepted, to: :rejected
      end
    end

  end
end

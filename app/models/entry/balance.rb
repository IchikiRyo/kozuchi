# -*- encoding : utf-8 -*-
class Entry::Balance < Entry::Base
  belongs_to :deal,
             :class_name => 'Deal::Balance',
             :foreign_key => 'deal_id'


  scope :without_initial, :conditions => {:initial_balance => false}

  validates :balance, :presence => true, :numericality => {:only_integer => true, :allow_blank => true}

  def balance=(a)
    self[:balance] = self.class.parse_amount(a)
  end

  def summary
    initial_balance? ? '残高確認（初回）' : '残高確認'
  end

  def partner_account_name
    initial_balance? ? '' : '不明金'
  end

end

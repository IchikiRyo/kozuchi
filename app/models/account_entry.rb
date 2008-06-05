# 口座への記入データクラス
class AccountEntry < ActiveRecord::Base
  belongs_to :deal,
             :class_name => 'BaseDeal',
             :foreign_key => 'deal_id'
  belongs_to :account,
             :class_name => 'Account::Base',
             :foreign_key => 'account_id'
  belongs_to :friend_link,
             :class_name => 'DealLink',
             :foreign_key => 'friend_link_id'
  validates_presence_of :amount
  attr_accessor :balance_estimated, :unknown_amount, :account_to_be_connected, :another_entry_account
  attr_reader :new_plus_link
  belongs_to :settlement
  belongs_to :result_settlement, :class_name => 'Settlement', :foreign_key => 'result_settlement_id'
  after_save :update_balance
  after_destroy :update_balance

  def settlement_attached?
    self.settlement || self.result_settlement
  end

  def another_account_entry
    deal.another_account_entry(self)
  end

  # ↓↓  call back methods  ↓↓

  # 新規作成時：フレンド連動があれば新しく作る
  def before_create
    create_friend_deal
  end
  
  def before_update
    if contents_updated?
      # リンクがあれば切る
      clear_friend_deal
      # 作る
      create_friend_deal
    end
  end

  def contents_updated?
    stored = AccountEntry.find(self.id)

    # 金額/残高が変更されていたら中身が変わったとみなす
    stored.amount.to_i != self.amount.to_i || stored.balance.to_i != self.balance.to_i
  end
  
  def before_destroy
    raise "精算データに紐づいているため削除できません。さきに精算データを削除してください。" if self.settlement || self.result_settlement
    p "before_destroy AccountEntry #{self.id}"
    clear_friend_deal
  end

  # ↑↑  call back methods  ↑↑
  
  # friend_deal とのリンクを消す。相手が未確定なら相手自身も消す。
  # 消したあとまた作られないようにstaticメソッドをつかう。
  def clear_friend_deal
    return unless friend_link
    another_entry = friend_link.another(self.id)
    friend_deal = another_entry.deal if another_entry
    
    # リンクを消す。
    AccountEntry.update_all("friend_link_id = null", "friend_link_id = #{self.friend_link_id}")
    DealLink.delete(self.friend_link_id)
  
    # このオブジェクトの状態更新
    self.friend_link_id = nil
    self.friend_link = nil
    
    # 相手があり、未確定なら相手も消す。連動して配下のentryをけすため destroy
    friend_deal.destroy if friend_deal && !friend_deal.confirmed
  end
  # TODO: Accountへの移動
  def self.balance_start(user_id, account_id, year, month)
    start_exclusive = Date.new(year, month, 1)
    Account.find(account_id).balance_before(start_exclusive) 
  end

#  def self.balance_at_the_start_of(user_id, account_id, start_exclusive)
#    # TODO: userに関する安全装置
#    account_id = account.id
#    AccountEntry.sum(:amount,
#      :joins => "inner join deals on account_entries.deal_id = deals.id",
#      :conditions => ["account_entries.user_id = ? and account_entries.account_id = ? and deals.date < ? ", user_id, account_id, start_exclusive]
#      ) || 0
#      
#    # 期限より前の最新の残高確認情報を取得する
#    entry = AccountEntry.find(:first,
#                      :select => "et.*",
#                      :conditions => ["et.user_id = ? and et.account_id = ? and dl.date < ? and et.balance is not null", user_id, account_id, start_exclusive],
#                      :joins => "as et inner join deals as dl on et.deal_id = dl.id",
#                      :order => "dl.date desc, dl.daily_seq")
#    # 期限より前に残高確認がない場合
#    if !entry
#      # 期限より後に残高確認があるか？
#      entry = AccountEntry.find(:first,
#                      :select => "et.*",
#                      :conditions => ["et.user_id = ? and et.account_id = ? and dl.date >= ? and et.balance is not null", user_id, account_id, start_exclusive],
#                      :joins => "as et inner join deals as dl on et.deal_id = dl.id",
#                      :order => "dl.date, dl.daily_seq")
#      # 期限より後にも残高確認がなければ、期限以前の異動合計を残高とする（初期残高０とみなす）。なければ０とする。
#      if !entry
#        return AccountEntry.sum("amount",
#                      :conditions => ["et.user_id = ? and account_id = ? and dl.date < ? and dl.confirmed = ?", user_id, account_id, start_exclusive, true],
#                      :joins => "as et inner join deals as dl on et.deal_id = dl.id"
#                      ) || 0
#      # 期限より後に残高確認があれば、期首から残高確認までの異動分をその残高から引いたものを期首残高とする
#      else
#        return entry.balance - (AccountEntry.sum("amount",
#                      :conditions => [
#                        "et.user_id = ? and account_id = ? and dl.date >= ? and (dl.date < ? or (dl.date =? and dl.daily_seq < ?)) and dl.confirmed = ?",
#                        user_id,
#                        account_id,
#                        start_exclusive,
#                        entry.deal.date,
#                        entry.deal.date,
#                        entry.deal.daily_seq,
#                        true],
#                      :joins => "as et inner join deals as dl on et.deal_id = dl.id"
#                       ) || 0)
#      end
#      
#    # 期限より前の最新残高確認があれば、それ以降の異動合計と残高を足したものとする。
#    else
#      return entry.balance + (AccountEntry.sum("amount",
#                             :conditions => ["et.user_id = ? and account_id = ? and dl.date < ? and (dl.date > ? or (dl.date =? and dl.daily_seq > ?)) and dl.confirmed = ?",
#                             user_id,
#                             account_id,
#                             start_exclusive,
#                             entry.deal.date,
#                             entry.deal.date,
#                             entry.deal.daily_seq,
#                             true],
#                      :joins => "as et inner join deals as dl on et.deal_id = dl.id"
#                             ) || 0)
#    end
#  end
  
  # 指定した取引位置での残高を計算する
  def self.balance_before(account_id, date, daily_seq)
    AccountEntry.sum(:amount,
      :joins => "inner join deals on account_entries.deal_id = deals.id",
      :conditions => ["account_entries.account_id = ? and (deals.date < ? or (deals.date = ? && deals.daily_seq < ?))", account_id, date, date, daily_seq]
      ) || 0
  end
  
  # リンクされたaccount_entry を返す
  def linked_account_entry
    return nil unless friend_link
    return friend_link.another(self.id)
  end
  
  def connected_account
    return AccountEntry.calc_connected_account(self.account, self.account_to_be_connected)
  end
  
  def self.calc_connected_account(account, account_to_be_connected)
    c = account_to_be_connected ? account.connected_accounts.detect{|e| e.id == account_to_be_connected.id} : nil
    if !c
      c = account.connected_accounts.size == 1 ? account.connected_accounts[0] : nil
    end
    return c
  end
  
  # 新しく連携先取引を作成する
  # connected_account が指定されていれば、それが連携対象となっていれば登録する
  # 指定されていなければ、連携対象が１つなら登録し、１つでなければ警告ログを吐いて登録しない
  def create_friend_deal
    return unless !friend_link_id # すでにある＝お手玉になる
    partner_account = connected_account
    return unless partner_account
    
    # 相方のentry の口座が渡されていれば、その連携先が同じユーザーでこのentryの連携先以外か調べる
    partner_other_account = connected_account_in_another_entry_other_than(partner_account)
    # ※相方の連携先がこの口座の連携先なら、default_assetを介して２つ作るままとする。
    # 相方 entry の連携先もこれから作る Deal となるため、相方用 deal_link を用意する。
    # この相方用 link は、相方処理のために取り出せるよう、インスタンス変数に格納しておく
    @new_plus_link = partner_other_account ? DealLink.create(:created_user_id => account.user_id) : nil
    
    # 二重接続でない場合の相方口座としては、先方ユーザーにおける受け皿設定があればそれを利用する。
    partner_other_account ||= partner_account.partner_account
    
    # それもなければ適当な資産口座を割り当てる。
    partner_other_account ||= partner_account.user.default_asset
    return unless partner_other_account
    
    new_minus_link = DealLink.create(:created_user_id => account.user_id)
    
    self.friend_link_id = new_minus_link.id
    
    friend_deal = Deal.new(
              :minus_account_id => partner_account.id,
              :minus_account_friend_link_id => new_minus_link.id,
              :plus_account_id => partner_other_account.id,
              :plus_account_friend_link_id => @new_plus_link ? @new_plus_link.id : nil,
              :amount => self.amount,
              :user_id => partner_account.user_id,
              :date => self.deal.date,
              :summary => self.deal.summary,
              :confirmed => false
    )
    friend_deal.save!
    
  end

  private

  def connected_account_in_another_entry_other_than(another_account)
    p "connected_account_in_another_entry_other_than : another_entry_account = #{self.another_entry_account}"
    return nil unless self.another_entry_account
    c = AccountEntry.calc_connected_account(self.another_entry_account, nil) # todo to_be_connected. ignore? 
    c = nil if c && (c.id == another_account.id || c.user.id != another_account.user.id)
    p "returned #{c}"
    return c
  end

  # 直後の残高記入のamountを再計算する
  def update_balance
    raise "could not get deal" unless deal
    next_balance_entry = AccountEntry.find(:first,
    :joins => "inner join deals on account_entries.deal_id = deals.id",
    :conditions => ["deals.type = 'Balance' and account_id = ? and (deals.date > ? or (deals.date = ? and deals.daily_seq > ?))", self.account_id, deal.date, deal.date, deal.daily_seq],
    :order => "deals.date, deals.daily_seq",
    :include => :deal)
    return unless next_balance_entry
    next_balance_entry.deal.update_amount # TODO: 効率
  end

end

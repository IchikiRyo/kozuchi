class SettlementSummaries

  attr_reader :years, :months, :previous_target_date, :next_target_date, :target_account

  # target_account がある場合は前・次の移動を出さない想定
  def initialize(user, target_account: nil, past: 9, future: 1, target_date: Time.zone.today)
    @target_date = target_date
    prepare_months(past: past, future: future, target_date: @target_date)

    @target_account = target_account

    unless @target_account
      @previous_target_date = @target_date << (past + future)
      @next_target_date = @target_date >> (past + future) if @target_date < Time.zone.today.beginning_of_month
    end


    scope = user.settlements.includes(:account, :result_entry => :deal).order('deals.date DESC, settlements.id DESC')
    scope = scope.where(account_id: target_account.id) if target_account
    all_summaries = scope.group_by(&:account)

    unless target_account
      @credit_accounts = user.assets.credit
      @credit_accounts.each do |account|
        all_summaries[account] = [] unless all_summaries.keys.include?(account)
      end
      all_summaries = all_summaries.sort{|(a, av), (b, bv)| a.sort_key <=> b.sort_key}
    end

    # summaries の values が、月 - 精算リストのハッシュになるようにする
    @summaries = {}
    all_summaries.each do |account, values|
      grouped = {}
      months.each do |monthly_date|
        grouped[monthly_date] = values.find_all{|s| s.result_entry.date.year == monthly_date.year && s.result_entry.date.month == monthly_date.month}
      end
      @summaries[account] = grouped
    end
  end

  def each(&block)
    @summaries.each(&block)
  end

  private

  # 月情報を用意する
  def prepare_months(past: 9, future: 1, target_date: Time.zone.today)
    @months = []
    date = start_date = target_date.beginning_of_month << past
    end_date = target_date.beginning_of_month >> future

    while date <= end_date
      @months << date
      date = date >> 1
    end
    @years = @months.group_by(&:year)
  end

end

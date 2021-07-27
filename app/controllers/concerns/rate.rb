module Rate
  require 'net/http'
  include Encrypt

  @@rate_state = false
  @@pairs = ["btcusd", "btceur", "ethusd", "etheur"]

  @@delay = 60

  @@th = nil

  def rate_start
    get_rate unless Thread.list.include?(@@th)
    @@rate_state = true
  end

  def rate_stop
    @@rate_state = false
  end

  def status
    @@rate_state
  end

  def get_exchange(pair)
    uri = URI("https://www.bitstamp.net/api/v2/ticker/#{pair}/")
    Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
      request = Net::HTTP::Get.new uri
      response = http.request request
      JSON(response.body)["last"].to_i
    end
  end

  def get_dynamics(exchange_value, coin_exchange, coin_deviation)
    calculated_deviation = calculate_deviation coin_exchange, coin_deviation
    if exchange_value < coin_exchange - calculated_deviation
      '▼'
    elsif exchange_value > coin_exchange + calculated_deviation
      '▲'
    else
      nil
    end
  end

  def calculate_deviation(coin_exchange, coin_deviation)
    (coin_exchange.to_f * coin_deviation.to_f)/100
  end

  def find_currency(pair, exchange_value)
    currency_name = pair[0..2]
    to_currency_name = pair[3..-1]
    to_currency = Coin.where(to_currency: currency_name).or(Coin.where(to_currency: to_currency_name))
    to_currency.map{|item|
      if item.currency == currency_name or item.currency == to_currency_name
        coin_exchange = item.exchange.value
        coin_deviation = item.exchange.deviation
        dynamics = get_dynamics(exchange_value, coin_exchange, coin_deviation)
        unless dynamics.nil?
          item.exchange.update(value: exchange_value)
          unless item.user.editable.status
            sending_conversion(pair, exchange_value, item, dynamics)
          end
        end
      end
    }
  end

  def sending_conversion(pair, rate_value, coin_item, dynamics = nil)
    coin = decrypt_coin(coin_item.coin).to_f
    if coin_item.currency == "btc" or coin_item.currency == "eth"
      converted = (rate_value * (coin - (coin * 0.049))).to_i
    else
      converted = (coin / rate_value).to_f.round(5)
    end
    begin
      Telegram.bot.send_message chat_id: coin_item.user.user,
                                parse_mode: "Markdown",
                                text: "#{dynamics} #{rate_value}#{I18n.t("telegram_webhooks.currencies.#{pair[3..-1]}")} ➔ #{converted}#{I18n.t("telegram_webhooks.currencies.#{coin_item.to_currency}")}"
    rescue
      p $!
    end
  end

  private

  def get_rate
    @@th = Thread.new do
      while @@rate_state
        for pair in @@pairs
          begin
            value = get_exchange pair
            find_currency pair, value
          rescue
            p $!
          end
        end
        sleep @@delay
      end
    end
  end

end
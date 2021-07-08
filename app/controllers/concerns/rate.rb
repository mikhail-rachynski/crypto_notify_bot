module Rate
  require 'net/http'
  require 'encrypt'

  @@rate_state = false
  @@pairs = ["btcusd", "btceur", "ethusd", "etheur"]

  @@range = {"btcusd" => 200, "btceur" => 200, "ethusd" => 10, "etheur" => 10}

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

  def checking_changes(pair, value)

    recorded_value = Exchenge.find_by(pair: pair)
    dynamics = nil
    if recorded_value.nil?
      Exchenge.create(pair: pair, value: value)
    else
      range = @@range[pair]
      if value < recorded_value.value - range
        dynamics = '▼'
      elsif value > recorded_value.value + range
        dynamics = '▲'
      end

      unless dynamics.nil?
        recorded_value.update(value: value)
        sending_exchange pair, value, dynamics
      end

    end
  end

  def sending_exchange(pair, rate_value, dynamics = nil)
    currency_name = pair[0..2]
    to_currency_name = pair[3..-1]
    to_currency = ToCurrency.where(currency: currency_name).or(ToCurrency.where(currency: to_currency_name))
    to_currency.map{|item| item.coin.find_each do |coin_item|
      if coin_item.currency == currency_name or coin_item.currency == to_currency_name
        user = coin_item.user
        unless user.editable.status
          coin = decrypt_coin(coin_item.coin).to_f
          if coin_item.currency == "btc" or coin_item.currency == "eth"
            converted = (rate_value * (coin - (coin * 0.049))).to_i
          else
            converted = (coin / rate_value).to_f.round(5)
          end

          bot.send_message chat_id: user.user,
                           text: "#{dynamics} #{rate_value}#{t("telegram_webhooks.currencies.#{to_currency_name}")} ➔ #{converted}#{t("telegram_webhooks.currencies.#{coin_item.to_currency[0].currency}")}"
        end

      end
    end
    }
  end

  private

  def get_rate
    @@th = Thread.new do
      while @@rate_state
        for pair in @@pairs
          begin
            uri = URI("https://www.bitstamp.net/api/v2/ticker/#{pair}/")
            Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
              request = Net::HTTP::Get.new uri
              response = http.request request
              value = JSON(response.body)["last"].to_i
              checking_changes pair, value
            end
          rescue
            p $!
          end
        end
        sleep @@delay
      end
    end
  end

end
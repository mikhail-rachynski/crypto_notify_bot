class TelegramWebhooksController < Telegram::Bot::UpdatesController
  include Telegram::Bot::UpdatesController::MessageContext
  include Encrypt
  include Rate
  before_action :switch_locale

  @@dialog_state = {
      bot_message_id: nil,
      user_id: nil,
      state: nil,
      coin_value: nil,
      currency: nil,
      to_currency: nil,
      pair: nil,
      exchange: nil,
      deviation: nil,
      mode: nil,
      editable_coin_id: nil,
      text_for_sending: nil
  }

  @@user = nil

  @@crypto_currencies = ["btc", "eth"]
  @@fiat_currencies = ["usd", "eur"]

  @@restart = nil
  @@cancel = nil

  def switch_locale
    if chat
      user = User.find_by(user: chat['id'])
      if user
        I18n.locale = user.locale || I18n.default_locale
      end
    else
      I18n.locale = I18n.default_locale
    end
    @@restart = {text: t(".buttons.start_over"), callback_data: 'restart'}
    @@cancel = {text: t(".buttons.cancel"), callback_data: 'cancel'}
  end

  def inline_sender(text, keyboard)
    message = respond_with :message, text: text.to_s,
                           parse_mode: "Markdown",
                           reply_markup: {
                               inline_keyboard: keyboard
                           }
    @@dialog_state[:bot_message_id] = message['result']['message_id']
  end

  # User commands
  def start!(*)
    bot.delete_message chat_id: chat['id'], message_id: payload['message_id']
    starting
  end

  def locale!(*)
    bot.delete_message chat_id: chat['id'], message_id: payload['message_id']
    locale_dialog
  end

  def stop!(*)
    bot.delete_message chat_id: chat['id'], message_id: payload['message_id']
    if User.find_by(user: chat['id'])
      text = t(".dialog.delete")
      inline_keyboard = [[{text: t(".buttons.yes"), callback_data: 'stop'}, @@cancel]]
    else
      text = t(".dialog.no_data")
      inline_keyboard = [[{text: t(".buttons.yes"), callback_data: 'add'}, @@cancel]]
    end

    inline_sender text, inline_keyboard
  end

  # Find user
  def starting
    @@dialog_state[:state] = "starting"
    @@user = User.new(user: chat['id'])
    unless @@user.save
      @@user = User.find_by user: chat['id']
      @@user.upd_editable true
      saved_exchanges_dialog
    else
      @@user.editable = Editable.create(status: true)
      locale_dialog
    end
  end

  # Admin commands

  def rate!(*args)
    admin_option 'rate'
  end

  def sender!(*args)
    admin_option 'sender'
  end

  def admin_option(action)
    @@dialog_state[:user_id] = chat['id']
    bot.delete_message chat_id: chat['id'], message_id: payload['message_id']
    @@user = User.find_by(user: chat['id'])

    if @@user.is_admin
      @@user.upd_editable true
      case action
      when 'rate'
        rate_status

      when 'sender'
        sender

      end
    else
      text = t(".admin.not_admin")
      inline_keyboard = [[@@cancel]]

      inline_sender text, inline_keyboard
    end
  end

  def rate_status
    text = t(".admin.status", status: status)
    inline_keyboard = [[{text: "#{status ? "Stop" : "Start"}",
                         callback_data: "#{status ? "stop_rate" : "start_rate"}"}],
                       [@@cancel]]

    inline_sender text, inline_keyboard
  end

  def sender
    @@dialog_state[:state] = "admin_sender"
    text = t(".admin.sender")
    inline_keyboard = [[@@cancel]]

    inline_sender text, inline_keyboard
  end

  # Dialogds

  def locale_dialog
    text = t(".dialog.choise_locale")
    inline_keyboard = [[{text: "Беларуская", callback_data: 'by'},
                        {text: "Русский", callback_data: 'ru'},
                        {text: "English", callback_data: 'en'}
                       ],
                       [@@cancel]]

    inline_sender text, inline_keyboard
  end

  def currencies_dialog
    @@dialog_state[:user_id] = chat['id']
    @@dialog_state[:mode] = "new"
    @@dialog_state[:state] = "currencies"

    text = t(".dialog.choice_currency")
    inline_keyboard = [[{text: "#{t(".currencies.btc")} BTC", callback_data: 'btc'},
                        {text: "#{t(".currencies.eth")} ETH", callback_data: 'eth'},
                        {text: "#{t(".currencies.usd")} USD", callback_data: 'usd'},
                        {text: "#{t(".currencies.eur")} EUR", callback_data: 'eur'}
                       ],
                       [@@cancel]]

    inline_sender text, inline_keyboard
  end

  def saved_exchanges_dialog
    @@dialog_state[:user_id] = chat['id']
    @@user = User.find_by(user: chat['id'])
    unless @@user.coin.empty?
      delete_buttons = []
      deviations = []
      exchanges = @@user.coin.map do |item|
        delete_buttons << {text: "🗑", callback_data: "del_#{item.id}"}
        deviations << {text: "⇅ #{item.exchange.deviation}%", callback_data: "edit_dev_#{item.id}"}
        {text: "#{item.currency.upcase} ➔ #{item.to_currency.upcase}",
         callback_data: "edit_all_#{item.id}"}
      end
      add_button = @@user.coin.length >= 3 ? [] : [{text: t(".buttons.add"), callback_data: 'add'}]
      text = t(".dialog.choise_saved")
      inline_keyboard = [exchanges, deviations, delete_buttons,
                         add_button,
                         [@@cancel]
      ]
      inline_sender text, inline_keyboard
    else
      currencies_dialog
    end
  end

  def set_sum_dialog()
    @@dialog_state[:state] = "set_sum"

    text = t(".dialog.enter_balance",
             currency: @@dialog_state[:currency].upcase)
    inline_keyboard = [[@@restart, @@cancel]]

    inline_sender text, inline_keyboard
  end

  def check_sum_dialog
    text = t(".dialog.check",
             balance: @@dialog_state[:coin_value] ,
             currency: @@dialog_state[:currency].upcase)
    inline_keyboard = [[
                           {text: t(".buttons.yes"),
                            callback_data: 'coin'},
                           {text: t(".buttons.change"),
                            callback_data: @@dialog_state[:currency]}
                       ],
                       [@@restart, @@cancel]]

    inline_sender text, inline_keyboard
  end

  def select_currency_for_conversion_dialog
    unless @@fiat_currencies.include?(@@dialog_state[:currency])
      currencies_to_convert = @@fiat_currencies
    else
      currencies_to_convert = @@crypto_currencies
    end
    currencies_to_convert = currencies_to_convert.map {|item|
      {text: "#{"✓" if @@dialog_state[:to_currency] == item} #{item.upcase}",
       callback_data: "sel_#{item}"}}

    text = t(".dialog.select_currency")
    inline_keyboard = [currencies_to_convert,
                       [
                           {text: t(".buttons.save"), callback_data: 'to_currency'}
                       ],
                       [@@restart, @@cancel]
    ]
    inline_sender text, inline_keyboard
  end

  def set_deviation_dialog
    @@dialog_state[:state] = "set_deviation"

    text = "#{t(".dialog.enter_deviation")} \n#{t(".dialog.old_deviation", deviation: @@dialog_state[:deviation]) if @@dialog_state[:mode] == "edit"}"
    inline_keyboard = [[@@restart, @@cancel]]
    inline_sender text, inline_keyboard
  end

  def check_deviation_dialog
    text = t(".dialog.check_deviation", deviation: @@dialog_state[:deviation])
    inline_keyboard = [[
                           {text: t(".buttons.yes"),
                            callback_data: 'deviation'},
                           {text: t(".buttons.change"),
                            callback_data: 'set_deviation'}
                       ],
                       [@@restart, @@cancel]]

    inline_sender text, inline_keyboard
  end

  def summarize_dialog
    coin = @@dialog_state[:coin_value]
    currency = @@dialog_state[:currency]
    deviation = @@dialog_state[:deviation]
    pair = @@dialog_state[:pair]
    @@dialog_state[:exchange] = get_exchange(pair)
    calculated_deviation = calculate_deviation @@dialog_state[:exchange], deviation

    text = t(".dialog.summary", coin: coin.to_s + currency.upcase,
             deviation: deviation,
             calculated_deviation: calculated_deviation.to_i.to_s + t(".currencies.#{pair[3..-1]}"),
             exchange: @@dialog_state[:exchange].to_s + t(".currencies.#{pair[3..-1]}"))
    inline_keyboard = [[
                           {text: t(".buttons.save"),
                            callback_data: 'save'},
                           @@cancel]]

    inline_sender text, inline_keyboard
  end

  def normalize_pair
    if @@crypto_currencies.include?(@@dialog_state[:currency])
      pair = @@dialog_state[:currency] + @@dialog_state[:to_currency]
    else
      pair = @@dialog_state[:to_currency] + @@dialog_state[:currency]
    end
    @@dialog_state[:pair] = pair
  end

  def serialize(coin)
    @@dialog_state[:editable_coin_id] = coin.id
    @@dialog_state[:coin_value] = decrypt_coin(coin.coin)
    @@dialog_state[:currency] = coin.currency
    @@dialog_state[:to_currency] = coin.to_currency
    @@dialog_state[:deviation] = coin.exchange.deviation
  end

  def callback_query(data)
    def delete_message
      bot.delete_message chat_id: chat['id'],
                         message_id: payload['message']['message_id']
    end

    case data
    when 'by', 'ru', 'en'
      User.find_by(user: chat['id']).update(locale: data)
      switch_locale
      answer_callback_query t(".answer.saved")
      starting if @@dialog_state[:state] == "starting"
      delete_message


    when 'add'
      currencies_dialog
      delete_message

    when 'btc', 'eth', 'usd', 'eur', 'error_set_sum'
      unless data == 'error_set_sum'
        @@dialog_state[:currency] = data
      end
      set_sum_dialog
      delete_message

    when 'coin'
      select_currency_for_conversion_dialog
      delete_message

    when "edit_all_#{data[9..-1] if data.scan("edit_all_")}",
        "edit_dev_#{data[9..-1] if data.scan("edit_dev_")}"
      @@dialog_state[:mode] = "edit"
      coin_id = data[9..-1]
      coin = Coin.find(coin_id)
      serialize coin
      normalize_pair
      delete_message
      if data[5..7] == "dev"
        set_deviation_dialog
      elsif data[5..7] == "all"
        check_sum_dialog
      end

    when "del_#{data[4..-1] if data.scan("del_")}"
      begin
        Coin.find(data[4..-1]).destroy
        answer_callback_query t(".answer.deleted")
        saved_exchanges_dialog
      rescue
        answer_callback_query t(".answer.previously_deleted")
      end
      delete_message


    when "sel_#{data[4..-1] if data.scan("sel_")}"
      delete_message
      @@dialog_state[:to_currency] = data[4..-1]
      select_currency_for_conversion_dialog

    when 'restart'
      starting
      delete_message

    when 'cancel'
      @@user.upd_editable false if @@user
      @@dialog_state.clear
      delete_message

    when 'to_currency'
      if @@dialog_state[:to_currency].nil?
        answer_callback_query t('.answer.end_currency'),
                              show_alert: true
        select_currency_for_conversion_dialog
      else
        normalize_pair
        @@dialog_state[:mode] == "edit" ? check_deviation_dialog : set_deviation_dialog
      end
      delete_message

    when 'set_deviation', 'error_set_deviation'
      set_deviation_dialog
      delete_message

    when 'deviation'
      summarize_dialog
      delete_message

    when 'save'
      if @@dialog_state[:mode] == "new"
        coin = Coin.create(currency: @@dialog_state[:currency],
                           user: @@user)

        coin.exchange = Exchange.create(value: @@dialog_state[:exchange])
      elsif @@dialog_state[:mode] = "edit"
        coin = Coin.find(@@dialog_state[:editable_coin_id])
      end
      coin.update(coin: encrypt_coin(@@dialog_state[:coin_value]),
                  to_currency: @@dialog_state[:to_currency])
      coin.exchange.update(deviation: @@dialog_state[:deviation])
      answer_callback_query t(".answer.saved")
      @@user.upd_editable false

      sending_conversion @@dialog_state[:pair], @@dialog_state[:exchange], coin, "✓"
      @@dialog_state.clear
      delete_message

    when 'stop'
      User.find_by(user: chat['id']).destroy
      delete_message

    when 'start_rate'
      rate_start
      delete_message

    when 'stop_rate'
      rate_stop
      delete_message

    when 'send_everyone'
      counter = []
      User.find_each do |user|
        begin
          message = bot.send_message chat_id: user.user,
                                     parse_mode: "Markdown",
                                     text: @@dialog_state[:text_for_sending]

          counter << true if message['ok']
        rescue
          p $!
        end
      end

      @@dialog_state[:text_for_sending] = nil
      bot.send_message chat_id: chat['id'],
                       parse_mode: "Markdown",
                       text: t(".admin.sended", to: counter.length, of: User.count)
      delete_message
    end
  end

  def delete_bot_message()
    bot.delete_message chat_id: @@dialog_state[:user_id],
                       message_id: @@dialog_state[:bot_message_id]
  end

  def message(message)
    bot.delete_message chat_id: chat['id'],
                       message_id: payload['message_id']

    state = @@dialog_state[:state]
    case state
    when 'set_sum', 'set_deviation'
      sum = message['text']
      unless sum.scan(/[^0,.0-9]/).empty?
        delete_bot_message

        text = t(".dialog.not_number")
        inline_keyboard = [
            [{text: 'Да', callback_data: "error_#{state}"}],[@@restart]
        ]
        inline_sender text, inline_keyboard
      else
        value = message['text'].gsub(/,/, '.')
        delete_bot_message

        case @@dialog_state[:state]
        when 'set_sum'
          @@dialog_state[:coin_value] = value
          select_currency_for_conversion_dialog
        when 'set_deviation'
          @@dialog_state[:deviation] = value
          summarize_dialog
        end

      end

    when 'admin_sender'
      delete_bot_message
      text = message["text"]
      inline_keyboard = [[{text: t(".admin.send_everyone"),
                           callback_data: "send_everyone"}],[@@cancel]]
      inline_sender text, inline_keyboard
      @@dialog_state[:text_for_sending] = text
    end
  end

  def action_missing(action, *_args)
    if action_type == :command
      respond_with :message,
                   text: t('telegram_webhooks.action_missing.command',
                           command: action_options[:command])
    end
  end

  def unsupported_payload_type()
    User.find_by(user: update["my_chat_member"]["chat"]["id"]).destroy if update["my_chat_member"]["new_chat_member"]["status"] == "kicked"
  end

end
class TelegramWebhooksController < Telegram::Bot::UpdatesController
  include Telegram::Bot::UpdatesController::MessageContext
  include Encrypt
  include Rate
  before_action :switch_locale


  @@dialog_state = {
      bot_current_message_id: nil,
      current_user_id: nil,
      current_state: nil,
      current_coin_value: nil,
      current_currency: nil,
      selected_currency: nil,
      mode: nil,
      editable_coin_id: nil,
      text_for_sending: nil
  }

  @@user = nil

  @@crypto_currencies = ["btc", "eth"]
  @@currencies = ["usd", "eur"]

  @@restart = nil
  @@cancel = nil

  def switch_locale
    I18n.locale = User.find_by(user: chat['id']).locale

    @@restart = {text: t(".buttons.start_over"), callback_data: 'restart'}
    @@cancel = {text: t(".buttons.cancel"), callback_data: 'cancel'}
  end

  def inline_sender(text, keyboard)

    message = respond_with :message, text: text.to_s,
                           parse_mode: "Markdown",
                           reply_markup: {
                               inline_keyboard: keyboard
                           }
    @@dialog_state[:bot_current_message_id] = message['result']['message_id']
  end

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

  def rate!(*args)
    admin_option 'rate'
  end

  def sender!(*args)
    admin_option 'sender'
  end

  def admin_option(action)
    @@dialog_state[:current_user_id] = chat['id']
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
    @@dialog_state[:current_state] = "admin_sender"
    text = t(".admin.sender")
    inline_keyboard = [[@@cancel]]

    inline_sender text, inline_keyboard
  end

  def starting
    @@user = User.new(user: chat['id'])

    unless @@user.save
      @@user = User.find_by user: chat['id']
      @@user.upd_editable true
      saved_exchanges
    else
      @@user.editable = Editable.create(status: true)
      locale_dialog
    end
  end

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
    @@dialog_state[:current_user_id] = chat['id']
    @@dialog_state[:mode] = "new"
    @@dialog_state[:current_state] = "currencies"

    text = t(".dialog.choice_currency")
    inline_keyboard = [[{text: "#{t(".currencies.btc")} BTC", callback_data: 'btc'},
                        {text: "#{t(".currencies.eth")} ETH", callback_data: 'eth'},
                        {text: "#{t(".currencies.usd")} USD", callback_data: 'usd'},
                        {text: "#{t(".currencies.eur")} EUR", callback_data: 'eur'}
                       ],
                       [@@cancel]]

    inline_sender text, inline_keyboard
  end

  def saved_exchanges
    @@dialog_state[:current_user_id] = chat['id']
    @@user = User.find_by(user: chat['id'])
    unless @@user.coin.empty?
      delete_buttons = []
      exchanges = @@user.coin.map do |item|
        delete_buttons << {text: "🗑", callback_data: "del_#{item.id}"}
        {text: "#{item.currency.upcase} ➔ #{item.to_currency[0].currency.upcase}",
         callback_data: "edit_#{item.id}"}
      end
      text = t(".dialog.choise_saved")
      inline_keyboard = [exchanges, delete_buttons,
                         [{text: t(".buttons.add"), callback_data: 'add'}],
                         [@@cancel]
      ]
      inline_sender text, inline_keyboard
    else
      currencies_dialog
    end
  end

  def set_sum()
    @@dialog_state[:current_state] = "set_sum"

    text = t(".dialog.enter_balance",
             currency: @@dialog_state[:current_currency].upcase)
    inline_keyboard = [[@@restart, @@cancel]]

    inline_sender text, inline_keyboard
  end

  def check_sum
    text = t(".dialog.check",
             balance: @@dialog_state[:current_coin_value] ,
             currency: @@dialog_state[:current_currency].upcase)
    inline_keyboard = [[
                           {text: t(".buttons.yes"),
                            callback_data: 'coin'},
                           {text: t(".buttons.change"),
                            callback_data: @@dialog_state[:current_currency]}
                       ],
                       [@@restart, @@cancel]]

    inline_sender text, inline_keyboard
  end

  def select_currency_for_conversion
    unless @@currencies.include?(@@dialog_state[:current_currency])
      currencies_to_convert = @@currencies
    else
      currencies_to_convert = @@crypto_currencies
    end
    currencies_to_convert = currencies_to_convert.map {|item|
      {text: "#{"✓" if @@dialog_state[:selected_currency] == item} #{item.upcase}",
       callback_data: "sel_#{item}"}}

    text = t(".dialog.select_currency")
    inline_keyboard = [currencies_to_convert,
                       [
                           {text: t(".buttons.save"), callback_data: 'save'}
                       ],
                       [@@restart, @@cancel]
    ]
    inline_sender text, inline_keyboard
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
      delete_message
      starting

    when 'add'
      delete_message
      currencies_dialog

    when 'btc', 'eth', 'usd', 'eur', 'error_sum'
      delete_message
      unless data == 'error_sum'
        @@dialog_state[:current_currency] = data
      end
      set_sum

    when 'coin'
      delete_message
      select_currency_for_conversion

    when "edit_#{data[5..-1] if data.scan("edit_")}"
      coin_id = data[5..-1]
      @@dialog_state[:mode] = "edit"
      @@dialog_state[:editable_coin_id] = coin_id
      coin = Coin.find(coin_id)
      @@dialog_state[:current_coin_value] = decrypt_coin(coin.coin)
      @@dialog_state[:current_currency] = coin.currency
      @@dialog_state[:selected_currency] = coin.to_currency[0].currency
      delete_message
      check_sum

    when "del_#{data[4..-1] if data.scan("del_")}"
      begin
        Coin.find(data[4..-1]).destroy
        answer_callback_query t(".answer.deleted")
        saved_exchanges
      rescue
        answer_callback_query t(".answer.previously_deleted")
      end
      delete_message


    when "sel_#{data[4..-1] if data.scan("sel_")}"
      delete_message
      @@dialog_state[:selected_currency] = data[4..-1]

      select_currency_for_conversion

    when 'restart'
      delete_message
      starting

    when 'cancel'
      delete_message
      @@user.upd_editable false if @@user
      @@dialog_state.clear

    when 'save'
      if @@dialog_state[:selected_currency].empty?
        answer_callback_query t(".answer.end_currency"),
                                show_alert: true
      else
        if @@dialog_state[:mode] == "new"
          coin = Coin.create(currency: @@dialog_state[:current_currency],
                             user: @@user)
        elsif @@dialog_state[:mode] = "edit"
          coin = Coin.find(@@dialog_state[:editable_coin_id])
        end
        coin.update(coin: encrypt_coin(@@dialog_state[:current_coin_value]))
        coin.to_currency.clear
        coin.to_currency << ToCurrency.find_by(currency: @@dialog_state[:selected_currency])

        answer_callback_query t(".answer.saved")
        @@user.upd_editable false

        delete_message
        pair = @@dialog_state[:current_currency] + @@dialog_state[:selected_currency]
        # sending_exchange pair, Exchenge.find_by(pair: pair).value, "✓"
        @@dialog_state.clear
      end

    when 'stop'
      User.find_by(user: chat['id']).destroy
      delete_message

    when 'start_rate'
      rate_start
      delete_message
      rate_status

    when 'stop_rate'
      rate_stop
      delete_message
      rate_status

    when 'send_all'
      User.find_each do |user|
        bot.send_message chat_id: user.user,
                         parse_mode: "Markdown",
                         text: @@dialog_state[:text_for_sending]
      end
      @@dialog_state[:text_for_sending] = nil
      delete_message

    end
  end

  def delete_bot_message()
    bot.delete_message chat_id: @@dialog_state[:current_user_id],
                       message_id: @@dialog_state[:bot_current_message_id]
  end

  def message(message)
    bot.delete_message chat_id: chat['id'],
                       message_id: payload['message_id']

    case @@dialog_state[:current_state]
    when 'set_sum'
      sum = message['text']
      unless sum.scan(/[^0.0-9]/).empty?
        delete_bot_message

        text = t(".dialog.non_zero")
        inline_keyboard = [
            [{text: 'Да', callback_data: 'error_sum'}],[@@restart]
        ]
        inline_sender text, inline_keyboard
      else
        @@dialog_state[:current_coin_value] = message['text']
        delete_bot_message
        check_sum
      end

    when 'admin_sender'
      delete_bot_message
      text = message["text"]
      inline_keyboard = [[{text: t(".admin.send_all"),
                           callback_data: "send_all"}],[@@cancel]]
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

end
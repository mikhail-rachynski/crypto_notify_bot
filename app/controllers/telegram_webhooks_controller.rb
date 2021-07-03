class TelegramWebhooksController < Telegram::Bot::UpdatesController
  include Telegram::Bot::UpdatesController::MessageContext
  include Encrypt
  include Rate


  @@dialog_state = {
      "bot_current_message_id" => nil,
      "current_user_id" => nil,
      "current_state" => nil,
      "current_coin_value" => nil,
      "current_currency" => nil,
      "selected_currency" => nil,
      "mode" => nil,
      "editable_coin_id" => nil
  }

  @@user = nil

  @@crypto_currencies = ["btc", "eth"]
  @@currencies = ["usd", "eur"]

  @@restart = {text: "Начать сначала", callback_data: 'restart'}
  @@cancel = {text: "Отмена", callback_data: 'cancel'}

  def inline_sender(text, keyboard)
    message = respond_with :message, text: text,
                           parse_mode: "Markdown",
                           reply_markup: {
                               inline_keyboard: keyboard
                           }
    @@dialog_state["bot_current_message_id"] = message['result']['message_id']
  end

  def start!(*)
    bot.delete_message chat_id: chat['id'], message_id: payload['message_id']
    starting
  end

  def stop!(*)
    bot.delete_message chat_id: chat['id'], message_id: payload['message_id']
    if User.find_by(user: chat['id'])
      text = "Удалить все данные?"
      inline_keyboard = [[{text: 'Да', callback_data: 'stop'}, @@cancel]]
    else
      text = "Ваших данных нет. Начать?"
      inline_keyboard = [[{text: 'Да', callback_data: 'add'}, @@cancel]]
    end

    inline_sender text, inline_keyboard
  end

  def rate!(*args)
    bot.delete_message chat_id: chat['id'], message_id: payload['message_id']
    @@user = User.find_by(user: chat['id'])

    if @@user.is_admin
      @@user.editable = Editable.create(status: true)
      rate_status
    end
  end

  def rate_status
    text = "*Статус:* #{status}"
    inline_keyboard = [[{text: "#{status ? "Stop" : "Start"}", callback_data: "#{status ? "stop_rate" : "start_rate"}"}
                       ],
                       [@@cancel]]

    inline_sender text, inline_keyboard
  end

  def starting
    @@user = User.new(user: chat['id'])

    unless @@user.save
      @@user = User.find_by user: chat['id']
      @@user.editable.update(status: true)
      saved_exchanges
    else
      @@user.editable = Editable.create(status: true)
      currencies_dialog
    end
  end

  def currencies_dialog
    @@dialog_state["current_user_id"] = chat['id']
    @@dialog_state["mode"] = "new"
    @@dialog_state["current_state"] = "currencies"

    text = "*Выберите тип вашей валюты:*"
    inline_keyboard = [[{text: "#{t('.currencies.btc')} BTC", callback_data: 'btc'},
                        {text: "#{t('.currencies.eth')} ETH", callback_data: 'eth'},
                        {text: 'Tether/USDT', callback_data: 'tether'}
                       ],
                       [@@cancel]]

    inline_sender text, inline_keyboard
  end

  def tether
    @@dialog_state["current_state"] = "teather"

    text = "Выберите валюту:"
    inline_keyboard = [[
                           {text: "#{t('.currencies.usd')} USD", callback_data: 'usd'},
                           {text: "#{t('.currencies.eur')} EUR", callback_data: 'eur'}
                       ],
                       [@@restart, @@cancel]]
    inline_sender text, inline_keyboard
  end

  def saved_exchanges
    @@dialog_state["current_user_id"] = chat['id']
    @@user = User.find_by(user: chat['id'])
    unless @@user.coin.empty?
      delete_buttons = []
      exchanges = @@user.coin.map do |item|
        delete_buttons << {text: "🗑", callback_data: "del_#{item.id}"}
        {text: "#{item.currency.upcase} ➔ #{item.to_currency[0].currency.upcase}", callback_data: "edit_#{item.id}"}
      end
      text = "*Выберите действия с вашими валютами:*"
      inline_keyboard = [exchanges, delete_buttons,
                         [{text: "Добавить", callback_data: 'add'}],
                         [@@cancel]
      ]
      inline_sender text, inline_keyboard
    else
      currencies_dialog
    end
  end

  def set_sum()
    @@dialog_state["current_state"] = "set_sum"

    text = "Введите баланс #{@@dialog_state["current_currency"].upcase}. (*Будет храниться в зашифрованном виде*)"
    inline_keyboard = [[@@restart, @@cancel]]

    inline_sender text, inline_keyboard
  end

  def check_sum
    text = "#{@@dialog_state["current_coin_value"]} #{@@dialog_state["current_currency"].upcase} - сохранить?"
    inline_keyboard = [[
                           {text: 'Да', callback_data: 'coin'},
                           {text: 'Изменить', callback_data: @@dialog_state["current_currency"]}
                       ],
                       [@@restart, @@cancel]]

    inline_sender text, inline_keyboard
  end

  def select_currency_for_conversion
    unless @@currencies.include?(@@dialog_state["current_currency"])
      currencies_to_convert = @@currencies
    else
      currencies_to_convert = @@crypto_currencies
    end
    currencies_to_convert = currencies_to_convert.map {|item|
      {text: "#{"✓" if @@dialog_state["selected_currency"] == item} #{item.upcase}",
       callback_data: "sel_#{item}"}}

    text = "Выберите валюту в которую хотите конвертировать:"
    inline_keyboard = [currencies_to_convert,
                       [
                           {text: "Сохранить", callback_data: 'save'}
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
    when 'tether'
      delete_message
      tether

    when 'add'
      delete_message
      currencies_dialog

    when 'btc', 'eth', 'usd', 'eur', 'error_sum'
      delete_message
      unless data == 'error_sum'
        @@dialog_state["current_currency"] = data
      end

      set_sum

    when 'coin'
      delete_message
      select_currency_for_conversion

    when "edit_#{data[5..-1] if data.scan("edit_")}"
      coin_id = data[5..-1]
      @@dialog_state["mode"] = "edit"
      @@dialog_state["editable_coin_id"] = coin_id
      coin = Coin.find(coin_id)
      @@dialog_state["current_coin_value"] = decrypt_coin(coin.coin)
      @@dialog_state["current_currency"] = coin.currency
      @@dialog_state["selected_currency"] = coin.to_currency[0].currency
      delete_message
      check_sum

    when "del_#{data[4..-1] if data.scan("del_")}"
      begin
        Coin.find(data[4..-1]).destroy
        answer_callback_query "Валюта удалена"
        saved_exchanges
      rescue
        answer_callback_query "Валюта уже была удалена"
      end
      delete_message


    when "sel_#{data[4..-1] if data.scan("sel_")}"
      delete_message
      @@dialog_state["selected_currency"] = data[4..-1]

      select_currency_for_conversion

    when 'restart'
      delete_message
      starting

    when 'cancel'
      delete_message
      @@user.editable.update(status: false) if @@user
      @@dialog_state.clear

    when 'save'
      if @@dialog_state["selected_currency"].empty?
        answer_callback_query "Должна быть выбрана конечная валюта", show_alert: true
      else
        if @@dialog_state["mode"] == "new"
          coin = Coin.create(currency: @@dialog_state["current_currency"],
                             user: @@user)
        elsif @@dialog_state["mode"] = "edit"
          coin = Coin.find(@@dialog_state["editable_coin_id"])
        end
        coin.update(coin: encrypt_coin(@@dialog_state["current_coin_value"]))
        coin.to_currency.clear
        coin.to_currency << ToCurrency.find_by(currency: @@dialog_state["selected_currency"])

        answer_callback_query "Сохранено!"
        @@user.editable.update(status: false)

        delete_message
        pair = @@dialog_state["current_currency"] + @@dialog_state["selected_currency"]
        sending_exchange pair, Exchenge.find_by(pair: pair).value, "✓"
        @@dialog_state["selected_currency"] = nil
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

    else
      answer_callback_query t('.no_alert')
    end
  end

  def delete_bot_message()
      bot.delete_message chat_id: @@dialog_state["current_user_id"],
                         message_id: @@dialog_state["bot_current_message_id"]
  end

  def message(message)
    bot.delete_message chat_id: chat['id'],
                       message_id: payload['message_id']

    case @@dialog_state["current_state"]
    when "set_sum"
      sum = message['text']
      unless sum.scan(/[^0.0-9]/).empty?
        delete_bot_message

        text = "Должно быть число больше 0. Ввести ещё раз?"
        inline_keyboard = [
                [{text: 'Да', callback_data: 'error_sum'}],[@@restart]
            ]
        inline_sender text, inline_keyboard
      else
        @@dialog_state["current_coin_value"] = message['text']
        delete_bot_message
        check_sum
      end
    end
  end

  def action_missing(action, *_args)
    if action_type == :command
      respond_with :message,
                   text: t('telegram_webhooks.action_missing.command', command: action_options[:command])
    end
  end

end
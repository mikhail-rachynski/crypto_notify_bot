class TelegramWebhooksController < Telegram::Bot::UpdatesController
  include Telegram::Bot::UpdatesController::MessageContext
  include Encrypt

  @@dialog_state = {
      "start_message_id" => nil,
      "current_user_id" => nil,
      "current_state" => nil,
      "current_coin" => nil,
      "current_currency" => nil,
      "selected_currencies" => []
  }

  @@user = nil
  @@currencies = ["btc", "eth", "usd", "eur"]

  @@restart = [{text: "Начать сначала", callback_data: 'restart'}]

  def start!(*)
    @@dialog_state["start_message_id"] = payload['message_id']
    @@dialog_state["current_user_id"] = chat['id']

    bot.delete_message chat_id: chat['id'], message_id: payload['message_id']

    @@user = User.new(user: chat['id'])

    unless @@user.save
      @@user = User.find_by user: chat['id']
    end

    currencies_dialog
  end

  def currencies_dialog
    @@dialog_state["current_state"] = "currencies"

    respond_with :message, text: "*Выберите тип вашей валюты:*",
                 parse_mode: "Markdown",
                 reply_markup: {
                     inline_keyboard: [
                         [
                             {text: '₿ BTC', callback_data: 'btc'},
                             {text: '⧫ ETH', callback_data: 'eth'},
                             {text: 'Tether/USDT', callback_data: 'tether'}
                         ]
                     ],
                 }
  end

  def tether
    @@dialog_state["current_state"] = "teather"

    respond_with :message, text: "Выберите валюту:", reply_markup: {
        inline_keyboard: [
            [
                {text: '$ USD', callback_data: 'usd'},
                {text: '€ EUR', callback_data: 'eur'}
            ],
            @@restart
        ]
    }
  end

  def set_sum()
    @@dialog_state["current_state"] = "set_sum"

    respond_with :message, text: "Введите количество #{@@dialog_state["current_currency"].upcase}", reply_markup: {
        inline_keyboard: [
            @@restart
        ]
    }
  end

  def select_currencies_for_conversion
    currencies = @@currencies.reject{|item| item == @@dialog_state["current_currency"]}
    currencies = currencies.map {|item|
      {text: "#{"✓" if @@dialog_state["selected_currencies"].include? item} #{item.upcase}",
       callback_data: "sel_#{item}"}}

    respond_with :message, text: "Выберите одну или несколько валют в которые хотите конвертировать:", reply_markup: {
        inline_keyboard: [
            currencies,
            [
                {text: "Сохранить", callback_data: 'save'}
            ],
            @@restart
        ]
    }
  end

  def help!(*)
    respond_with :message, text: t('.conte  nt')
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

    when 'btc', 'eth', 'usd', 'eur', 'error_sum'
      delete_message
      unless data == 'error_sum'
        @@dialog_state["current_currency"] = data
      end

      set_sum

    when 'coin'
      delete_message
      select_currencies_for_conversion

    when "sel_#{data[4..-1] if data.scan("sel_")}"
      delete_message
      selected_currencies = @@dialog_state["selected_currencies"]
      currency = data[4..-1]

      if selected_currencies.include? currency
        selected_currencies.delete currency
      else
        selected_currencies << currency
      end

      select_currencies_for_conversion
    when 'restart'
      delete_message
      currencies_dialog

    when 'save'
      if @@dialog_state["selected_currencies"].empty?
        answer_callback_query "Должна быть выбрана конечная валюта", show_alert: true
      else

        coin = Coin.create(coin: encrypt_coin(@@dialog_state["current_coin"]),
                           currency: @@dialog_state["current_currency"],
                           user: @@user)
        @@dialog_state["selected_currencies"].map do |item|
          coin.to_currency << ToCurrency.find_by(currency: item)
        end
        answer_callback_query "Поздравляем! Вы подписаны!", show_alert: true
        delete_message
      end

    else
      answer_callback_query t('.no_alert')
    end
  end

  def delete_all_messages(current_message_id)
    for i in @@dialog_state["start_message_id"]...current_message_id
      begin
        bot.delete_message chat_id: @@dialog_state["current_user_id"], message_id: i
      rescue
        p $!
      end
    end
  end

  def message(message)
    bot.delete_message chat_id: chat['id'],
                       message_id: payload['message_id']

    case @@dialog_state["current_state"]
    when "set_sum"
      sum = message['text']
      p sum.scan(/[^0-9]]/)
      unless sum.scan(/[^0.0-9]/).empty?
        delete_all_messages payload['message_id']

        respond_with :message, text: "Должно быть число больше 0. Ввести ещё раз?",
                     parse_mode: "Markdown",
                     reply_markup: {
                         inline_keyboard: [
                             [
                                 {text: 'Да', callback_data: 'error_sum'}
                             ],
                             @@restart
                         ],
                     }
      else
        @@dialog_state["current_coin"] = message['text']

        delete_all_messages payload['message_id']

        respond_with :message, text: "#{message['text']} #{@@dialog_state["current_currency"].upcase} - это верно?",
                     parse_mode: "Markdown",
                     reply_markup: {
                         inline_keyboard: [
                             [
                                 {text: 'Да', callback_data: 'coin'},
                                 {text: 'Изменить', callback_data: @@dialog_state["current_currency"]}
                             ],
                             @@restart
                         ],
                     }
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
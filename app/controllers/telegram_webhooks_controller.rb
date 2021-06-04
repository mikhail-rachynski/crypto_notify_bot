class TelegramWebhooksController < Telegram::Bot::UpdatesController
  include Telegram::Bot::UpdatesController::MessageContext

  @@dialog_state = {
      "current_user_id" => nil,
      "current_state" => nil,
      "current_dialog_message_id" => nil,
      "current_coin" => nil,
      "current_currency" => nil
  }

  @@user = nil

  def start!(*)
    @@dialog_state["current_dialog_message_id"] = payload['message_id']
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
            [
                {text: "Начать сначала", callback_data: 'back'}
            ]
        ]
    }
  end

  def set_sum(value)
    @@dialog_state["current_state"] = "set_sum"
    respond_with :message, text: "Введите количество #{@@dialog_state["current_currency"]} и нажмите ОК", reply_markup: {
        inline_keyboard: [
            [
                {text: 'OK', callback_data: 'save'},
                {text: 'Начать сначала', callback_data: 'back'}
            ]
        ]
    }
  end

  def help!(*)
    respond_with :message, text: t('.conte  nt')
  end

  def callback_query(data)
    bot.delete_message chat_id: chat['id'], message_id: payload['message']['message_id']
    case data
    when 'tether'
      tether
    when 'btc', 'eth', 'usd', 'eur'
      @@dialog_state["current_currency"] = data
      set_sum data
    when 'back'
      currencies_dialog
    when 'save'
      Coin.create(coin: @@dialog_state["current_coin"], currency: @@dialog_state["current_currency"], user: @@user)
    else
      answer_callback_query t('.no_alert')
    end
  end

  def message(message)
    bot.delete_message chat_id: chat['id'], message_id: payload['message_id']
    case @@dialog_state["current_state"]
    when "set_sum"
      if message['text'].to_i == 0
        respond_with :message, text: "Должно быть число больше 0. Ввести ещё раз?",
                     parse_mode: "Markdown",
                     reply_markup: {
                         inline_keyboard: [
                             [
                                 {text: 'Да', callback_data: 'yes_number_error'},
                                 {text: 'Начать сначала', callback_data: 'back'}
                             ]
                         ],
                     }
      else
        @@dialog_state["current_coin"] = message['text']
      #   respond_with :message, text: "#{message['text']} #{@@dialog_state["current_currency"]} - это верно?",
      #                parse_mode: "Markdown",
      #                reply_markup: {
      #                    inline_keyboard: [
      #                        [
      #                            {text: 'Да', callback_data: 'save'},
      #                            {text: 'Изменить', callback_data: 'change'},
      #                            {text: 'Начать сначала', callback_data: 'back'}
      #                        ]
      #                    ],
      #                }
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

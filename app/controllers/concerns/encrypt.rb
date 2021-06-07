module Encrypt
  require 'openssl'
  require "base64"

  @@iv = ENV['BOT_ENCRYPT_IV']
  @@key = ENV['BOT_ENCRYPT_KEY']

  def encrypt_coin(data)
    cipher = OpenSSL::Cipher.new('aes256')
    cipher.encrypt
    cipher.key = @@key
    cipher.iv = @@iv
    Base64.encode64(cipher.update(data) + cipher.final)
  end

  def decrypt_coin(data)
    data = Base64.encode64(data)
    decipher = OpenSSL::Cipher.new('aes256')
    decipher.decrypt
    decipher.key = @@key
    decipher.iv = @@iv
    decipher.update(data) + decipher.final
  end

end
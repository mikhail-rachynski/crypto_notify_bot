# Crypto notify bot
This bot converts your crypto balance and notify at changed exchange rate
## Commands
##### User commands
- `/start` - Start or edit your subscribes.
- `/stop` - Stop subscribes and remove your data.
- `/locale` - Change your language
##### Admin commands
- `/rate` - Start exchange rate getter.
- `/sender` - Send message for everyone subscribers.
## Run
```
bin/rake telegram:bot:poller
```
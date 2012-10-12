app = require './app'

process.on 'uncaughtException', (ex) ->
  console.log 'Uncaught exception', ex.message
  console.log ex.stack
  process.exit 1

app.run()

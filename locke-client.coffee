request = require 'request'

module.exports = (host) ->
  createUser: (app, username, password, callback) ->
    request.post
      url: host + '/createUser'
      json:
        app: app
        email: username
        password: password
    , (err, res, body) ->
      return callback(err) if err
      callback(null, body)
  authPassword: (app, username, password, ttl, callback) ->
    request.post
      url: host + '/authPassword'
      json:
        app: app
        email: username
        password: password
        secondsToLive: ttl
    , (err, res, body) ->
      return callback(err) if err
      callback(null, body)
  authToken: (app, username, token, callback) ->
    request.post
      url: host + '/authToken'
      json:
        app: app
        email: username
        token: token
    , (err, res, body) ->
      return callback(err) if err
      callback(null, body)


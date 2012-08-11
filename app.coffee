db = require 'manikin-mongodb'
apa = require 'rester'
async = require 'async'
nconf = require 'nconf'
mongojs = require 'mongojs'
viaduct = require 'viaduct-server'
_ = require 'underscore'
_.mixin require 'underscore.plus'


if process.env.NODE_ENV == 'production'

  lockeMock = require './locke-client'

  lockeAuth = (username, token, callback) ->
    lockeMock.authToken 'sally', username, token, (err, res) ->
      callback(err, true)

else

  lockeMock = require '../locke/src/expoapi'

  lockeMock.mockApp = (app, callback) ->
    email = 'owning-user-' + app
    password = 'allfornought'
    lockeMock.createUser 'locke', email, password, ->
      lockeMock.authPassword 'locke', email, password, 86400, (err, res) ->
        lockeMock.createApp email, res.token, app, callback

  lockeAuth = (username, password, callback) ->
    lockeMock.authPassword 'sally', username, password, 86400, (err, res) ->
      return callback(err) if err
      return callback(null, false) if !res.token?
      lockeMock.authToken 'sally', username, res.token, (err, res) ->
        callback(err, true)






api = db.create()


getUserConnection = null

getUserFromDb = (req, callback) ->
  if !getUserConnection
    getUserConnection = mongojs.connect nconf.get('mongo'), Object.keys(mod)

  if !req.headers.authorization
    callback(null, null)
    return

  code = req.headers.authorization.slice(6)
  au = new Buffer(code, 'base64').toString('ascii').split(':')
  username = au[0]
  token = au[1]

  lockeAuth username, token, (err, authed) ->
    return callback(null, null) if err || !authed

    async.map ['admins', 'users'], (collection, callback) ->
      getUserConnection[collection].find { username: username }, callback
    , (err, results) ->
      if err
        callback(null, null)
        return

      if results[1].length > 0
        callback(null, { account: results[1][0].account, id: results[1][0]._id, accountAdmin: results[1][0].accountAdmin })
        return

      if results[0].length > 0
        callback(null, { admin: true })
        return

      callback(null, null)

adminWrap = (f) -> (user) ->
  return null if !user?
  return {} if user.admin
  return f(user)


defaultAuth = (targetProperty) -> adminWrap (user) ->
  return _.makeObject(targetProperty || 'account', user.account) if user.account
  return null


valUniqueInModel = (model, property) -> (value, callback) ->
  api.list model, _.makeObject(property, value), (err, data) ->
    callback(!err && data.length == 0)




mod =
  accounts:
    auth: defaultAuth('id')
    authWrite: adminWrap (user) -> if user.accountAdmin then { id: user.account } else null
    authCreate: adminWrap (user) -> null
    naturalId: 'name'
    fields:
      name: { type: 'string', required: true, unique: true }

  admins:
    auth: adminWrap (user) -> null
    fields:
      username:
        type: 'string'
        required: true
        unqiue: true
        validate: valUniqueInModel('users', 'username')

  users:
    auth: adminWrap (user) -> if user.accountAdmin then { account: user.account } else { id: user.id }
    authCreate: adminWrap (user) -> if user.accountAdmin then { account: user.account } else null
    owners: account: 'accounts'
    fields:
      username:
        type: 'string'
        required: true
        unique: true
        validate: valUniqueInModel('admins', 'username')
      accountAdmin: { type: 'boolean', default: false }

  companies:
    auth: defaultAuth()
    owners: account: 'accounts'
    fields:
      name: { type: 'string', default: '' }
      orgnr: { type: 'string', default: '' }
      address: { type: 'string', default: '' }
      zip: { type: 'string', default: '' }
      city: { type: 'string', default: '' }
      notes: { type: 'string', default: '' }
      about: { type: 'string', default: '' }

  projects:
    auth: defaultAuth()
    owners: company: 'companies'
    fields:
      description: { type: 'string', default: '' }
      value: { type: 'number', default: null }

  calls:
    auth: defaultAuth()
    owners: company: 'companies'
    fields:
      notes: { type: 'string', default: '' }

  meetings:
    auth: defaultAuth()
    owners: company: 'companies'
    fields:
      notes: { type: 'string', default: '' }

      # This is a many-to-many relationship. The name of the attribute must be unique among
      # models and other many-to-many relationships as it will be used as a url-component.
      # Write a check for it and write a test that proves it.
      attendees: { type: 'hasMany', model: 'contacts' }

      origin:
        type: 'hasOne'
        model: 'calls'

        # Denna validering är någon form av "common ancestor".
        # I och med redundansen så är det väldigt lätt att generalisera.
        # commonAncestors: ['company']
        validation: (meeting, call, callback) ->
          if meeting.company.toString() != call.company.toString()
            callback 'The origin call does not belong to the same company as the meeting'
          callback()

  contacts:
    auth: defaultAuth()
    owners: company: 'companies'
    fields:
      notes: { type: 'string', default: '' }
      name:  { type: 'string', default: '' }
      phone: { type: 'string', default: '' }
      email: { type: 'string', default: '' }




Object.keys(mod).forEach (modelName) ->
  api.defModel modelName, mod[modelName]


exports.run = (settings, callback) ->

  express = require 'express'

  app = express.createServer()
  app.use express.bodyParser()
  app.use express.responseTime()
  app.use viaduct.connect()


  nconf.env().argv().defaults
    mongo: 'mongodb://localhost/sally'
    NODE_ENV: 'development'
    port: 3000

  console.log("Starting up")
  console.log("Environment mongo:", nconf.get('mongo'))
  console.log("Environment NODE_ENV:", nconf.get('NODE_ENV'))
  console.log("Environment port:", nconf.get('port'))

  api.connect nconf.get('mongo'), (err) ->
    if err
      console.log "ERROR: Could not connect to db"
      return

    # Bootstrap an admin if there are none
    api.list 'admins', { }, (err, data) ->
      if err
        console.log err
        return

      onGo = ->

        # I signup-processen så måste ju locke komma in på något sätt
        # Alternativ att klienten skapar ett locke-konto samtidigt
        apa.verb app, 'signup', (req, res) ->
          api.post 'accounts', { name: req.body.account }, (err, accountData) ->
            if err
              apa.respond(req, res, { err: 'Could not create account' }, 400)
              return

            accountId = accountData.id.toString()
            lockeMock.createUser 'sally', req.body.username, req.body.password, ->
              api.post 'users', { account: accountId, username: req.body.username, accountAdmin: true }, (err, userData) ->
                if err
                  api.delOne 'accounts', { id: accountId }, (err, delData) ->
                    apa.respond(req, res, { err: 'Could not create user' }, 400)
                else
                  if mod.accounts.naturalId?
                    accountData.id = accountData[mod.accounts.naturalId]
                  apa.respond(req, res, accountData)

        app.post '/admins', (req, res, next) ->
          username = req.body.username
          password = req.body.password
          lockeMock.createUser 'sally', username, password, ->
            next()

        app.post '/accounts/:account/users', (req, res, next) ->
          username = req.body.username || ''
          password = req.body.password || ''
          lockeMock.createUser 'sally', username, password, ->
            next()

        apa.exec app, api, getUserFromDb, mod
        app.listen nconf.get('port')
        callback()

      if data.length > 0
        onGo()
      else
        lockeMock.mockApp 'sally', ->
          lockeMock.createUser 'sally', 'admin0', 'admin0', ->
            console.log arguments
            api.post 'admins', { username: 'admin0', password: 'admin0' }, (err) ->
              if err
                console.log(err)
                process.exit(1)
              else
                onGo()

process.on 'uncaughtException', (ex) ->
  console.log 'Uncaught exception:', ex.message
  console.log ex.stack
  process.exit 1

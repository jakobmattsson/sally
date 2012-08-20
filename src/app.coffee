db = require 'manikin-mongodb'
apa = require 'rester'
async = require 'async'
nconf = require 'nconf'
mongojs = require 'mongojs'
viaduct = require 'viaduct-server'
_ = require 'underscore'
_.mixin require 'underscore.plus'


sharpLocke = process.env.NODE_ENV == 'production'
lockeHost = if sharpLocke then 'https://locke.nodejitsu.com' else 'http://localhost:6002'
locke = require('../locke-client')(lockeHost)



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

  locke.authToken 'sally', username, token, (err, res) ->
    return callback(null, null) if err || res?.status != 'OK'

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
    # naturalId: 'name'
    fields:
      name: { type: 'string', required: true, unique: true }

  admins:
    auth: adminWrap (user) -> null
    defaultSort: 'username'
    fields:
      username: { type: 'string', required: true, unique: true, validate: valUniqueInModel('users', 'username') }

  users:
    auth: adminWrap (user) -> if user.accountAdmin then { account: user.account } else { id: user.id }
    authCreate: adminWrap (user) -> if user.accountAdmin then { account: user.account } else null
    owners: account: 'accounts'
    defaultSort: 'username'
    fields:
      username: { type: 'string', required: true, unique: true, validate: valUniqueInModel('admins', 'username') }
      nickname: { type: 'string', default: '' }
      accountAdmin: { type: 'boolean', default: false }

  companies:
    auth: defaultAuth()
    owners: account: 'accounts'
    defaultSort: 'name'
    fields:
      name: { type: 'string', default: '' }
      orgnr: { type: 'string', default: '' }
      address: { type: 'string', default: '' }
      zip: { type: 'string', default: '' }
      city: { type: 'string', default: '' }
      notes: { type: 'string', default: '' }
      website: { type: 'string', default: '' }
      about: { type: 'string', default: '' }
      nextCall: { type: 'date' }
      nextCallStrict: { type: 'boolean' }
      seller: { type: 'hasOne', model: 'users' }

  projects:
    auth: defaultAuth()
    owners: company: 'companies'
    fields:
      description: { type: 'string', default: '' }
      value: { type: 'number', default: null }

  emails:
    auth: defaultAuth()
    owners: company: 'companies'
    defaultSort: 'when'
    fields:
      body: { type: 'string', default: '' }
      when: { type: 'date', required: false }
      seller: { type: 'hasOne', model: 'users', required: false }
      contact: { type: 'hasOne', model: 'contacts', required: false }

  calls:
    auth: defaultAuth()
    owners: company: 'companies'
    defaultSort: 'when'
    fields:
      notes: { type: 'string', default: '' }
      answered: { type: 'boolean' }
      when: { type: 'date', required: false }
      seller: { type: 'hasOne', model: 'users', required: false }
      contact: { type: 'hasOne', model: 'contacts', required: false }

  meetings:
    auth: defaultAuth()
    owners: company: 'companies'
    defaultSort: 'when'
    fields:
      notes: { type: 'string', default: '' }
      when: { type: 'date', default: '' }
      origin:
        type: 'hasOne'
        model: 'calls'
        validation: (meeting, call, callback) ->
          if meeting.company.toString() != call.company.toString()
            callback 'The origin call does not belong to the same company as the meeting'
          callback()
      # This is a many-to-many relationship. The name of the attribute must be unique among
      # models and other many-to-many relationships as it will be used as a url-component.
      # Write a check for it and write a test that proves it.
      attendingContacts: { type: 'hasMany', model: 'contacts' }
      attendingSellers: { type: 'hasMany', model: 'users' }

  contacts:
    auth: defaultAuth()
    owners: company: 'companies'
    defaultSort: 'name'
    fields:
      notes: { type: 'string', default: '' }
      name:  { type: 'string', default: '' }
      role:  { type: 'string', default: '' }
      phone: { type: 'string', default: '' }
      email: { type: 'string', default: '' }
      primary: { type: 'boolean', default: false }




Object.keys(mod).forEach (modelName) ->
  api.defModel modelName, mod[modelName]


exports.run = (settings, callback) ->

  express = require 'express'

  app = express.createServer()
  app.use express.bodyParser()
  app.use express.responseTime()
  app.use viaduct.connect()

  nconf.env().argv().overrides(settings).defaults
    mongo: 'mongodb://localhost/sally'
    port: 3000

  console.log("Starting up")
  console.log("Environment mongo:", nconf.get('mongo'))
  console.log("Environment NODE_ENV:", process.env.NODE_ENV)
  console.log("Environment port:", nconf.get('port'))

  api.connect nconf.get('mongo'), (err) ->
    return console.log "ERROR: Could not connect to db" if err

    # Bootstrap an admin if there are none
    api.list 'admins', { }, (err, data) ->
      return console.log err if err

      onGo = ->

        # TODO: This whole method must be tested in a much more exhaustive way.
        apa.verb app, 'signup', (req, res) ->

          api.getOne 'users', { username: req.body.username }, (err, data) ->
            if data?
              return locke.createUser 'sally', req.body.username || '', req.body.password || '', (err, data) ->
                #err is not enough
                if err?
                  apa.respond(req, res, { err: 'Could not create user' }, 400)
                  return

                apa.respond(req, res, { whatever: 'should return something useful here' })

            api.post 'accounts', { name: req.body.account || 'randomName' + new Date().getTime() }, (err, accountData) ->
              if err
                apa.respond(req, res, { err: 'Could not create account' }, 400)
                return

              accountId = accountData.id.toString()
              api.post 'users', { account: accountId, username: req.body.username, accountAdmin: true }, (err, userData) ->
                if err?
                  api.delOne 'accounts', { id: accountId }, (err, delData) ->
                    apa.respond(req, res, { err: 'Could not create user' }, 400)
                  return

                locke.createUser 'sally', req.body.username || '', req.body.password || '', (err, data) ->
                  # err is not enough. "data" can contain a bad http status code.
                  if err?
                    api.delOne 'accounts', { id: accountId }, (err, delData) ->
                      api.delOne 'users', { id: userData.id.toString() }, (err, delData) ->
                        apa.respond(req, res, { err: 'Could not create account' }, 400)
                    return

                  if mod.accounts.naturalId?
                    accountData.id = accountData[mod.accounts.naturalId]
                  apa.respond(req, res, accountData)

        # behövs denna?
        app.post '/admins', (req, res, next) ->
          username = req.body.username
          password = req.body.password
          locke.createUser 'sally', username, password, ->
            next()

        # behövs denna?
        app.post '/accounts/:account/users', (req, res, next) ->
          username = req.body.username || ''
          password = req.body.password || ''
          locke.createUser 'sally', username, password, ->
            next()

        # speciale
        # app.post '/auth', (req, res) ->
        #   getUserFromDb req, () ->
        #     res.json({ code: 200, body: { err: null, hej: 'san' } } )

        apa.exec app, api, getUserFromDb, mod
        app.listen nconf.get('port')
        callback()



      wrapOnGo = (go) ->
        return go if sharpLocke
        () ->
          async.forEach ['admins', 'users'], (collection, callback) ->
            api.list collection, (err, data) ->
              async.forEach data, (user, callback) ->
                locke.createUser 'sally', user.username, 'summertime', (err, data) ->
                  return callback(err) if err
                  return callback(data.status) if data.status != 'OK' && data.status != 'The given email is already in use for this app'
                  callback()
              , callback
          , (err) ->
            go()
      onGo = wrapOnGo(onGo)

      if data.length > 0
        onGo()
      else
        console.log("Bootstrapping an admin...")
        api.post 'admins', { username: 'admin0' }, (err) ->
          if err
            console.log(err)
            process.exit(1)
          else
            onGo()

process.on 'uncaughtException', (ex) ->
  console.log 'Uncaught exception:', ex.message
  console.log ex.stack
  process.exit 1

db = require 'manikin-mongodb'
apa = require 'rester'
async = require 'async'
nconf = require 'nconf'
mongojs = require 'mongojs'
underline = require 'underline'
viaduct = require 'viaduct-server'

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
  password = au[1]

  async.map ['admins', 'users'], (collection, callback) ->
    getUserConnection[collection].find { username: username, password: password }, callback
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
  return underline.makeObject(targetProperty || 'account', user.account) if user.account
  return null


valUniqueInModel = (model, property) -> (value, callback) ->
  api.list model, underline.makeObject(property, value), (err, data) ->
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
    fieldFilter: (user) -> ['password']
    fields:
      username:
        type: 'string'
        required: true
        unqiue: true
        validate: valUniqueInModel('users', 'username')
      password: { type: 'string', required: true }

  users:
    auth: adminWrap (user) -> if user.accountAdmin then { account: user.account } else { id: user.id }
    authCreate: adminWrap (user) -> if user.accountAdmin then { account: user.account } else null
    owners: account: 'accounts'
    fieldFilter: (user) -> ['password']
    fields:
      username:
        type: 'string'
        required: true
        unique: true
        validate: valUniqueInModel('admins', 'username')
      password: { type: 'string', required: true }
      accountAdmin: { type: 'boolean', default: false }

  companies:
    auth: defaultAuth()
    owners: account: 'accounts'
    fields:
      name: { type: 'string', default: '' }
      notes: { type: 'string', default: '' }
      address: { type: 'string', default: '' }

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
        apa.verb app, 'signup', (req, res) ->
          api.post 'accounts', { name: req.body.account }, (err, accountData) ->
            if err
              apa.respond(req, res, { err: 'Could not create account' }, 400)
              return

            accountId = accountData.id.toString()
            api.post 'users', { account: accountId, username: req.body.username, password: req.body.password, accountAdmin: true }, (err, userData) ->
              if err
                api.delOne 'accounts', { id: accountId }, (err, delData) ->
                  apa.respond(req, res, { err: 'Could not create user' }, 400)
              else
                if mod.accounts.naturalId?
                  accountData.id = accountData[mod.accounts.naturalId]
                apa.respond(req, res, accountData)

        apa.exec app, api, getUserFromDb, mod
        app.listen nconf.get('port')
        callback()

      if data.length > 0
        onGo()
      else
        api.post 'admins', { username: 'admin', password: 'admin' }, (err) ->
          if err
            console.log(err)
            process.exit(1)
          else
            onGo()

process.on 'uncaughtException', (ex) ->
  console.log 'Uncaught exception:', ex.message
  console.log ex.stack
  process.exit 1

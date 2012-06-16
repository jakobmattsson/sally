db = require './db'
apa = require './core'
async = require 'async'
nconf = require 'nconf'
underline = require 'underline'

api = db.create()
model = api.defModel

getUserFromDb = (req, callback) ->
  mongojs = require 'mongojs'
  db = mongojs.connect 'mongodb://localhost/sally', Object.keys(mod)

  if !req.headers.authorization
    callback(null, false)
    return

  code = req.headers.authorization.slice(6)
  au = new Buffer(code, 'base64').toString('ascii').split(':')
  username = au[0]
  password = au[1]

  async.map ['admins', 'users'], (collection, callback) ->
    db[collection].find { username: username, password: password }, callback
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
  model modelName, mod[modelName]


exports.run = (settings, callback) ->

  express = require 'express'

  app = express.createServer()
  app.use express.bodyParser()


  nconf.env().argv().defaults
    mongo: 'mongodb://localhost/sally'
    NODE_ENV: 'development'
    port: 3000

  console.log("Starting up")
  console.log("Environment mongo:", nconf.get('mongo'))
  console.log("Environment NODE_ENV:", nconf.get('NODE_ENV'))

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
            api.postSub 'users', { username: req.body.username, password: req.body.password, accountAdmin: true }, 'account', accountId, (err, userData) ->
              if err
                api.del 'accounts', accountId, (err, delData) ->
                  apa.respond(req, res, { err: 'Could not create user' }, 400)
              else
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

process.on 'uncaughtException', (exception) ->
  console.log "Uncaught exception"
  console.log exception

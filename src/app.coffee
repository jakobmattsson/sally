Q = require 'q'
path = require 'path'
manikin = require 'manikin-mongodb'
rester = require 'rester'
async = require 'async'
nconf = require 'nconf'
_ = require 'underscore'
_.mixin require 'underscore.plus'
express = require 'express'
lockeClient = require 'locke-client'
resterTools = require 'rester-tools'



# Model support
# =============================================================================

adminWrap = (f) -> (user) ->
  return null if !user?
  return {} if user.admin
  return f(user)


defaultAuth = (targetProperty) -> adminWrap (user) ->
  if user.account then _.makeObject(targetProperty || 'account', user.account) else null


valUniqueInModel = (model, property) -> (db, value, callback) ->
  db.list model, _.makeObject(property, value), (err, data) ->
    callback(!err && data.length == 0)



# Models
# =============================================================================

models =
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
    auth: defaultAuth()
    authWrite: adminWrap (user) -> if user.accountAdmin then { account: user.account } else { id: user.id }
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



# Custom routes
# =============================================================================

signupFunc = (db, app, locke) ->
  rester.verb app, 'signup', (req, res) ->

    db.getOne 'users', { username: req.body.username }, (err, data) ->
      if data?
        return locke.createUser 'sally', req.body.username || '', req.body.password || '', (err, data) ->
          if err? || data?.status != 'OK'
            rester.respond(req, res, { err: 'Could not create user' }, 400)
            return

          rester.respond(req, res, { whatever: 'should return something useful here' })

      db.post 'accounts', { name: req.body.account || 'randomName' + new Date().getTime() }, (err, accountData) ->
        if err
          rester.respond(req, res, { err: 'Could not create account' }, 400)
          return

        accountId = accountData.id.toString()
        db.post 'users', { account: accountId, username: req.body.username, accountAdmin: true }, (err, userData) ->
          if err?
            db.delOne 'accounts', { id: accountId }, (err, delData) ->
              rester.respond(req, res, { err: 'Could not create user' }, 400)
            return

          locke.createUser 'sally', req.body.username || '', req.body.password || '', (err, data) ->
            if err? || data?.status != 'OK'
              db.delOne 'accounts', { id: accountId }, (err, delData) ->
                rester.respond(req, res, { err: 'Could not create user' }, 400)
              return

            if models.accounts.naturalId?
              accountData.id = accountData[models.accounts.naturalId]
            rester.respond(req, res, accountData)



# Application entry point
# =============================================================================

exports.run = (settings, callback) ->

  # Reading and echoing the configuration for the application
  settings ?= {}
  callback ?= ->

  nconf.env().argv().overrides(settings).defaults
    mongo: 'mongodb://localhost/sally'
    PORT: settings.port || 3000

  console.log "Starting up..."
  console.log "* mongo: " + nconf.get('mongo')
  console.log "* environment: " + process.env.NODE_ENV
  console.log "* port: " + nconf.get('PORT')

  # Creating the interface to the database
  db = manikin.create()

  # Setting up the express app
  app = express.createServer()
  app.use express.bodyParser()
  app.use express.responseTime()
  app.use resterTools.versionMid path.resolve(__dirname, '../package.json')

  # Setting up locke
  sharpLocke = process.env.NODE_ENV == 'production'
  locke = lockeClient(if sharpLocke then 'https://locke.nodejitsu.com' else 'http://localhost:6002') # TODO: must set up https for lockeapp.com so the proper DNS (abstracting underlying provider) can be used

  # Defining where user are stored in the models and how to get them
  userModels = [
    table: 'users'
    usernameProperty: 'username'
    callback: (r) -> { account: r.account, id: r.id, accountAdmin: r.accountAdmin }
  ,
    table: 'admins'
    usernameProperty: 'username'
    callback: (r) -> { admin: true }
  ]
  getUserFromDb = resterTools.authUser(
    resterTools.authenticateWithBasicAuthAndLocke(locke, 'sally')
    resterTools.getAuthorizationData(db, userModels)
  )

  # Registering all models
  db.defModels models

  # Connecting to the database
  Q.ninvoke(db, 'connect', nconf.get('mongo'))
  .fail ->
    console.log "ERROR: Could not connect to db"

  # Creating a default admin in case there are none
  .then ->
    Q.ninvoke(db, 'list', 'admins', {})
  .then (data) ->
    if data.length == 0
      console.log("Bootstrapping an admin...")
      Q.ninvoke(db, 'post', 'admins', { username: 'admin0' })
  .fail (err) ->
    console.log(err)
    process.exit(1)

  #  Adding users to locke if it's being mocked
  .then ->
    return if sharpLocke
    Q.ninvoke(resterTools, 'getAllUsernames', db, userModels)
    .then (usernames) ->
      Q.ninvoke(resterTools, 'createLockeUsers', locke, 'sally', 'summertime', usernames)
    .end()

  # Adding custom routes to the app
  .then ->

    signupFunc(db, app, locke) # TODO: This whole method must be tested in a much more exhaustive way.

    app.post '/admins', (req, res, next) -> # TODO: behövs denna hjälpmetod?
      username = req.body.username
      password = req.body.password
      locke.createUser 'sally', username, password, ->
        next()

    app.post '/accounts/:account/users', (req, res, next) -> # TODO: behövs denna hjälpmetod?
      username = req.body.username || ''
      password = req.body.password || ''
      locke.createUser 'sally', username, password, ->
        next()

    app.get '/auth', (req, res) ->
      getUserFromDb req, (err, status) ->
        res.json({ authenticated: status? })

  # Starting up the server
  .then ->
    rester.exec app, db, getUserFromDb, models
    app.listen nconf.get('PORT')
    console.log "Ready!"
    callback()
  .end()

# Lägg till statiska filer, tex /favicon.ico



# AUTHENTICATION
# Ägarskap är aldrig föränderligt (detta gör många saker mycket lättare)
# Förusatt att authentication alltid baseras på ägarskapsheirarkin så kan med fylla ut alla objekt med redundans
# Den här redundansen kan sedan användas för att avgöra om man har tillgång till objektet eller ej


# Borde testa att indirekta ägare också kopieras över när man lägger till ett nytt löv i heirarkin


# Natural IDs. En kolumn som är sträng eller integer och unik över hela modellen kan användas som nyckel.
# Borde finnas en option för att göra just det.
# Först och främst behöver jag en option för att säga att en kolumn ska vara unik.

# Many-to-many relations

# Making a super simple GUI (just tables)
# JSONP-friendly
# Getting it to run properly on nodejitsu, with their mongodb

# Måste kunna skriva "pre"- och "post"-middleware här i denna filen. För tex auth.

# Nested data structures (tänk prowikes översättningar)

# Many-to-many:
# * vilka kontakter var på mötet?
# * vilken kontakt ringde jag?
# * vilka av våra anställda var det som ringde samtalet eller gick på mötet?

# LIST meetings/1234/contacts
# LIST calls/1234/contacts

# POST meetings/1234/contacts/567
# DEL meetings/1234/contacts/567

# Det kan absolut få finnas data i den här relationen. Den kan man sätta med POST, uppdatera med PUT och läsa med GET som vanligt

# Kontakterna som kopplas ihop med ett möte måste valideras så att båda formerna av resurser hör till samma company

# Se till att vanliga användare (eller icke-authade) inte kan skapa account genom en vanlig /POST

db = require './db'
apa = require './core'
async = require 'async'
nconf = require 'nconf'
underline = require 'underline'

api = db.create()
model = api.defModel


# Nu
# * Tillämpa auth i alla routes (kommer kräva att testerna patchas upp)

# man för att göra detta behöver man väl olika säkerhetsnivåer?
# tänk tex på att skapa ett account, det ska man kunna göra även om man inte är inloggad
# (kanske inte i denna appen, men föreställ situationen först åtminstone)

# jag skulle skapat en special-route, som skapade en användare och ett konto som en atomisk operation och som
# tillät vem som helst att göra det.

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


defaultAuth = (targetProperty) -> (user) ->
  # null means: you must authorize yourself
  # {} means: you are allowed access to every object in the collection
  # any other object means: you are allowed access to those objects matching the given object
  return null if !user?
  return {} if user.admin
  return underline.makeObject(targetProperty || 'account', user.account) if user.account
  return null


valUniqueInModel = (model, property) -> (value, callback) ->
  api.list model, underline.makeObject(property, value), (err, data) ->
    callback(!err && data.length == 0)

mod =
  accounts:
    auth: defaultAuth('id')
    fields:
      name: { type: 'string', default: '' }

  admins:
    auth: (user) -> if user?.admin then {} else null
    fieldFilter: (user) -> ['password']
    fields:
      username:
        type: 'string'
        required: true
        unqiue: true
        validate: valUniqueInModel('users', 'username')
      password: { type: 'string', required: true }

  users:
    auth: (user) ->
      return null if !user?
      return {} if user.admin
      return { id: user.id } if !user.accountAdmin
      return { account: user.account }
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

  nconf.env().argv().defaults
    mongo: 'mongodb://localhost/sally'
    NODE_ENV: 'development'
    # port: 3000 (och 80 i nodejitsus env)

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

      if data.length > 0
        apa.exec api, getUserFromDb, mod
        callback()
      else
        api.post 'admins', { username: 'admin', password: 'admin' }, (err) ->
          if err
            console.log(err)
            process.exit(1)
          else
            apa.exec api, getUserFromDb, mod
            callback()

process.on 'uncaughtException', (exception) ->
  console.log "Uncaught exception"
  console.log exception

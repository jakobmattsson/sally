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

db = require './db'
apa = require './core'
async = require 'async'

api = db.create()
model = api.defModel


# Nu
# * Tillämpa auth i alla routes (kommer kräva att testerna patchas upp)

# man för att göra detta behöver man väl olika säkerhetsnivåer?
# tänk tex på att skapa ett account, det ska man kunna göra även om man inte är inloggad
# (kanske inte i denna appen, men föreställ situationen först åtminstone)

# jag skulle skapat en special-route, som skapade en användare och ett konto som en atomisk operation och som
# tillät vem som helst att göra det.

api.getUserFromDb = (db, req, callback) ->
  mongojs = require 'mongojs'

  if !req.headers.authorization
    callback(null, false)
    return

  code = req.headers.authorization.slice(6)
  au = new Buffer(code, 'base64').toString('ascii').split(':')
  username = au[0]
  password = au[1]

  # gör en sökning i admin-tabellen
  #models[model].find filter, callback
  # prova sedan att skapa användare etc i gränssnittet


  async.map ['admins', 'users'], (collection, callback) ->
    db[collection].find { username: username, password: password }, callback
  , (err, results) ->
    if err
      callback(null, null)
      return

    if results[1].length > 0
      callback(null, { account: results[1].account })
      return

    if results[0].length > 0
      callback(null, { admin: true })
      return

    if username == 'admin' && password == 'admin'
      callback(null, { admin: true })
      return

    callback(null, null)

  # db.admins.find { username: username, password: password }, (err, docs) ->
  #   console.log "res admins", docs
  #
  # db.users.find { username: username, password: password }, (err, docs) ->
  #   console.log "res users", docs
  #
  # if username == 'admin' && password == 'admin'
  #   callback(null, { admin: true })
  #   return
  #
  # # just nu funkar inte auth i harvester.
  # # det beror nog på att det körs med ajax. Kan man svara på 401 med ajax?
  #
  #
  # # gör en sökning i users-tabellen
  #
  # if username == 'jakob' && password == 'test'
  #   callback(null, { account: '4fd2f6c81cfc8b8ab4000003' })
  #   return
  #
  # callback(null, null)


defaultAuth = (targetProperty) -> (user) ->
  # null betyder: autha dig!
  # {} betyder: du får tillgång till alla
  # annat objekt betyder: du får tillgång till det som filtret tillåter

  targetProperty = targetProperty || 'account'

  return null if !user?
  return {} if user.admin

  filter = {}
  filter[targetProperty] = user.account

  return filter if user.account
  return null



mod =
  accounts:
    auth: defaultAuth('_id') # jobbigt att det behöver vara "_id" istället för "id"
    fields:
      name: { type: 'string', default: '' }

  admins:
    auth: (user) -> if user? && user.admin then {} else null
    fields:
      username: { type: 'string', default: '' }
      password: { type: 'string', default: '' }

  users:
    auth: defaultAuth() # implementera korrekt. vem kan se alla? vem kan ändra data? vem kan ändra lösenord?
    owners:
      account: 'accounts'
    fields:
      username: { type: 'string', default: '' }
      password: { type: 'string', default: '' }
      accountAdmin: { type: 'boolean', default: '' } # boolska typer!

  companies:
    auth: defaultAuth()
    owners:
      account: 'accounts'
    fields:
      name: { type: 'string', default: '' }
      notes: { type: 'string', default: '' }
      address: { type: 'string', default: '' }

  projects:
    auth: defaultAuth()
    owners:
      company: 'companies'
    fields:
      description: { type: 'string', default: '' }
      value: { type: 'number', default: null }

  calls:
    auth: defaultAuth()
    owners:
      company: 'companies'
    fields:
      notes: { type: 'string', default: '' }

  meetings:
    auth: defaultAuth()
    owners:
      company: 'companies'
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
    owners:
      company: 'companies'
    fields:
      notes: { type: 'string', default: '' }
      name:  { type: 'string', default: '' }
      phone: { type: 'string', default: '' }
      email: { type: 'string', default: '' }




Object.keys(mod).forEach (modelName) ->
  model modelName, mod[modelName]

api.connect 'mongodb://localhost/sally4'
apa.exec(api)


# account <- company <- meetings/calls/contacts/projects

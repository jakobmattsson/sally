# AUTHENTICATION
# Ägarskap är aldrig föränderligt (detta gör många saker mycket lättare)
# Förusatt att authentication alltid baseras på ägarskapsheirarkin så kan med fylla ut alla objekt med redundans
# Den här redundansen kan sedan användas för att avgöra om man har tillgång till objektet eller ej


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

api = db.create()
model = api.defModel


# Man måste definiera hur man får ut en user
# Borde gå att köra antingen med token ELLER med basicAuth. börja med basic.



# givet ett user-objekt (vad det innehåller plockas fram centralt), skapa ett filter som kan användas mot kollektionen
model 'accounts',
  auth: (user) ->
    if user.admin then {} else { id: user.account }
  fields:
    name: { type: 'string', default: '' }

model 'companies',
  owners:
    account: 'accounts'
  auth: (user) ->
    if user.admin then {} else { account: user.account }
  fields:
    name: { type: 'string', default: '' }
    notes: { type: 'string', default: '' }
    address: { type: 'string', default: '' }

# inför redundans för att ha tillgång till account här också
model 'projects',
  owners:
    company: 'companies'
  fields:
    description: { type: 'string', default: '' }
    value: { type: 'number', default: null }

# inför redundsans för att ha tillgång till account här också
model 'calls',
  owners:
    company: 'companies'
  fields:
    notes: { type: 'string', default: '' }

model 'meetings',
  owners:
    company: 'companies'
  fields:
    notes: { type: 'string', default: '' }

    # This is a many-to-many relationship. The name of the attribute must be unique among
    # models and other many-to-many relationships as it will be used as a url-component.
    attendees: { type: 'hasMany', model: 'contacts' }

    origin:
      type: 'hasOne'
      model: 'calls'
      validation: (meeting, call, callback) ->
        if meeting.company.toString() != call.company.toString()
          callback 'The origin call does not belong to the same company as the meeting'
        callback()

model 'contacts',
  owners:
    company: 'companies'
  fields:
    notes: { type: 'string', default: '' }
    name:  { type: 'string', default: '' }
    phone: { type: 'string', default: '' }
    email: { type: 'string', default: '' }


api.connect 'mongodb://localhost/sally4'
apa.exec(api)

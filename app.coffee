# Many-to-many relations

# Authentication

# Making a super simple GUI (just tables)
# Cross-domain: CORS
# JSONP-friendly
# Getting it to run properly on nodejitsu, with their mongodb

# Måste kunna skriva "pre"- och "post"-middleware här i denna filen. För tex auth.

# Nested data structures (tänk prowikes översättningar)

# Hur gör man en meta-request (för att få veta valideringar, relationer etc) på bästa sätt?

# Many-to-many:
# * vilka kontakter var på mötet?
# * vilken kontakt ringde jag?
# * vilka av våra anställda var det som ringde samtalet eller gick på mötet?

# LIST meetings/1234/contacts
# LIST calls/1234/contacts

# POST meetings/1234/contacts/567
# DEL meetings/1234/contacts/567

# Det kan absolut få finnas data i den här relationen. Den kan man sätta med POST, uppdatera med PUT och läsa med GET som vanligt

db = require './db'
apa = require './core'

api = db.create()
model = api.defModel


model 'accounts', { }
  name: { type: 'string', default: '' }

model 'companies', { account: 'accounts' }
  name: { type: 'string', default: '' }
  notes: { type: 'string', default: '' }
  address: {
    type: 'nested',
    street: { type: 'string', default: '' }
    city: { type: 'string', default: '' }
    country: { type: 'string', default: '' }
  }

model 'projects', { company: 'companies' }
  description: { type: 'string', default: '' }
  value: { type: 'number', default: null }

model 'calls', { company: 'companies' }
  notes: { type: 'string', default: '' }

model 'meetings', { company: 'companies' }
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

model 'contacts', { company: 'companies' }
  notes: { type: 'string', default: '' }
  name:  { type: 'string', default: '' }
  phone: { type: 'string', default: '' }
  email: { type: 'string', default: '' }



api.connect 'mongodb://localhost/sally2'
apa.exec(api)

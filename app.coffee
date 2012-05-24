# Many-to-many relations
# Tar man bort ett call så ska det möte som hör till det call:et få sin referens nullad.

# Förhindra att man uppdaterar IDn
# Jag vill att id-fältet heter "id" istället för "_id"

# Authentication

# Making a super simple GUI (just tables)
# Cross-domain: CORS
# Getting it to run properly on nodejitsu, with their mongodb

# Måste kunna skriva "pre"- och "post"-middleware här i denna filen. För tex auth.


apa = require './core'
defModel = apa.defModel


defModel 'companies', {}
  name:
    type: String
    default: ''
  notes:
    type: String
    default: ''

defModel 'projects', { company: 'companies' }
  description:
    type: String
    default: ''
  value:
    type: Number
    default: null

defModel 'calls', { company: 'companies' }
  notes:
    type: String
    default: ''

defModel 'meetings', { company: 'companies' }
  notes:
    type: String
    default: ''
  origin:
    ref: 'calls'
    'x-validation': (meeting, call, callback) ->
      if meeting.company.toString() != call.company.toString()
        callback new Error 'The origin call does not belong to the same company as the meeting'
      callback()

defModel 'contacts', { company: 'companies' }
  notes:
    type: String
    default: ''
  name:
    type: String
    default: ''
  phone:
    type: String
    default: ''
  email:
    type: String
    default: ''


apa.exec()

should = require 'should'
helpers = require './testhelpers'
query = (text) -> helpers.query(text, { origin: 'http://localhost:3000' })
save = (name) -> (data) -> this[name] = data.id



query('Root')
.get('/')
.res('Get root', (data) -> data.should.eql { roots: ['accounts', 'admins'], verbs: [] })
.run()



query('No resource')
.get('/accounts')
.err(401, 'unauthed')
.run()



query('No resource')
.auth('invalid', 'invalid')
.get('/accounts')
.err(401, 'unauthed')
.run()



query('No resource')
.auth('admin', 'admin')
.get('/accounts')
.res('Got accounts')
.run()



query('No resource')
.get('/foobar')
.err(400, 'No such resource')
.run()


query('No id')
.get('/companies/123456781234567812345678')
.err(400, 'No such id')
.run()


query('Testing so invalid IDs return the same error message as nonexisting IDs')
.get('/companies/1234')
.err(400, 'No such id')
.run()



query('Creating companies')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', (data) -> data.should.have.keys ['id', 'notes', 'name', 'address', 'account'])
.run()



query('Attempting to save nonexisting field')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { nonExistingField: 'something', another: 2 })
.err(400, "Invalid fields: nonExistingField, another")
.run()



query('Ensure that PUT-operations are atomic')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { notes: 'original notes' })
.put('/companies/#{company}', { notes: 'real data', foobar: 'fake data' })
.err(400, "Invalid fields: foobar")
.get('/companies/#{company}')
.res('Getting the original data', (data) -> data.notes.should.eql 'original notes')
.run()



query('Attempting to override id')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { id: '123456781234567812345678' })
.err(400)
.run()



query('Attempting to override _id')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { _id: '123456781234567812345678' })
.err(400)
.run()



query('Cascading delete')
.auth('admin', 'admin')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Creating company', save 'company')
.get('/calls')
.res('Getting calls', (data) -> @calls = data.length)
.get('/contacts')
.res('Getting contacts', (data) -> @contacts = data.length)
.post('/companies/#{company}/calls')
.post('/companies/#{company}/calls')
.post('/companies/#{company}/contacts')
.get('/companies/#{company}/calls')
.res('Getting company calls', (data) -> data.length.should.eql 2)
.get('/calls')
.res('Getting calls again', (data) -> data.length.should.eql @calls + 2)
.get('/companies/#{company}/contacts')
.res('Getting company contacts', (data) -> data.length.should.eql 1)
.get('/contacts')
.res('Getting contacts again', (data) -> data.length.should.eql @contacts + 1)
.del('/companies/#{company}')
.get('/companies/#{company}')
.err(400, 'No such id')
.del('/companies/#{company}')
.err(400, 'No such id')
.get('/companies/#{company}/calls')
.res('Calls once again', (data) -> data.length.should.eql 0)
.get('/companies/#{company}/contacts')
.res('Contacts once again', (data) -> data.length.should.eql 0)
.get('/calls')
.res('Getting calls', (data) -> data.length.should.eql @calls)
.get('/contacts')
.res('Getting contacts', (data) -> data.length.should.eql @contacts)
.run()



query('Meeting pointing to a valid call or nothing')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.post('/companies/#{company}/calls')
.res('Created call', save 'call1')
.post('/companies/#{company}/calls')
.res('Created call', save 'call2')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company2')
.post('/companies/#{company2}/calls')
.res('Created call', save 'call3')
.post('/companies/#{company2}/calls')
.res('Created call', save 'call4')
.post('/companies/#{company}/meetings')
.res('Created meeting', save 'meeting')
.put('/meetings/#{meeting}', { notes: 'abc' })
.res('Updated meeting', (data) -> data.notes.should.eql 'abc')
.put('/meetings/#{meeting}', { origin: 123 })
.err(400, 'Error: Invalid ObjectId')
.put('/meetings/#{meeting}', () -> { origin: @call1 })
.res('Set origin to call1')
.put('/meetings/#{meeting}', () -> { origin: @call2 })
.res('Set origin to call2')
.put('/meetings/#{meeting}', () -> { origin: @call3 })
.err(400, 'Error: The origin call does not belong to the same company as the meeting')
.put('/meetings/#{meeting}', () -> { origin: @call4 })
.err(400, 'Error: The origin call does not belong to the same company as the meeting')
.run()



query('Nulling foreign keys when pointed item is removed')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.post('/companies/#{company}/calls')
.res('Created call', save 'call1')
.post('/companies/#{company}/calls')
.res('Created call', save 'call2')
.post('/companies/#{company}/meetings')
.res('Created meeting', save 'meeting')
.put('/meetings/#{meeting}', () -> { origin: @call1 })
.res('Set origin to call1')
.get('/meetings/#{meeting}')
.res('Getting meeting referring to call1', (data) -> data.origin.should.eql @call1)
.del('/calls/#{call1}')
.get('/meetings/#{meeting}')
.res('Getting meeting referring to nothing', (data) -> should.not.exist data.origin)
.run()



query('Create many-to-many relation')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.post('/companies/#{company}/contacts').res('Created first contact', save 'contact1')
.post('/companies/#{company}/contacts').res('Created second contact', save 'contact2')
.post('/companies/#{company}/meetings').res('Created meeting', save 'meeting')
.post('/meetings/#{meeting}/attendees/#{contact1}')
.res('Settings first contact to meeting', (data) -> data.should.eql {})
.post('/attendees/#{contact2}/meetings/#{meeting}')
.res('Settings second contact to meeting', (data) -> data.should.eql {})
.get('/meetings/#{meeting}/attendees')
.res('Getting all meeting attendees', (data) ->
  data.should.have.lengthOf 2
  data[0].should.include { company: @company, id: @contact1 }
  data[1].should.include { company: @company, id: @contact2 }
)
.get('/attendees/#{contact1}/meetings')
.res('Getting the meetings from an attendant', (data) -> data.should.eql [{
  attendees: [@contact1, @contact2]
  company: @company
  notes: ''
  id: @meeting
}])
.del('/meetings/#{meeting}/attendees/#{contact1}')
.res('Removed contact from meeting', (data) -> data.id.should.eql @contact1)
.del('/attendees/#{contact2}/meetings/#{meeting}')
.res('Removed meeting from contact', (data) -> data.id.should.eql @meeting)
.get('/companies/#{company}/contacts')
.res('All contacts should still be in the db', (data) -> data.length.should.eql 2)
.get('/companies/#{company}/meetings')
.res('All meetings should still be in the db', (data) -> data.length.should.eql 1)
.get('/meetings/#{meeting}/attendees')
.res('Getting all meeting attendees', (data) -> data.should.eql [])
.run()



query('Test meta owns')
.get('/meta/accounts').res('Meta for accounts', (data) -> data.owns.should.eql ['users', 'companies'])
.get('/meta/companies').res('Meta for companies', (data) -> data.owns.should.eql ['projects', 'calls', 'meetings', 'contacts'])
.get('/meta/calls').res('Meta for calls', (data) -> data.owns.should.eql [])
.get('/meta/meetings').res('Meta for meetings', (data) -> data.owns.should.eql [])
.get('/meta/projects').res('Meta for projects', (data) -> data.owns.should.eql [])
.get('/meta/contacts').res('Meta for contacts', (data) -> data.owns.should.eql [])
.run()


query('Test meta fields')
.get('/meta/accounts').res('Meta fields for accounts', (data) -> data.fields.should.eql [{ name: 'id', type: 'string', readonly: true }, { name: 'name', type: 'string', readonly: false }])
.get('/meta/projects').res('Meta fields for projects', (data) -> data.fields.should.eql [{ name: 'account', type: 'string', readonly: true }, { name: 'company', type: 'string', readonly: true }, { name: 'description', type: 'string', readonly: false }, { name: 'id', type: 'string', readonly: true }, { name: 'value', type: 'number', readonly: false }])
.get('/meta/companies').res('Meta fields for companies', (data) -> data.fields.should.eql [{ name: 'account', type: 'string', readonly: true }, { name: 'address', type: 'string', readonly: false }, { name: 'id', type: 'string', readonly: true }, { name: 'name', type: 'string', readonly: false }, { name: 'notes', type: 'string', readonly: false }])
.run()



query('Creating users')
.post('/accounts')
.res('Created account', save 'account')
.post('/accounts/#{account}/users')
.res('Created user', (data) -> data.should.include { username: '', password: '', accountAdmin: false })
.run()






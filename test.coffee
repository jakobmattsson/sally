should = require 'should'
helpers = require './testhelpers'
query = (text) -> helpers.query(text, { origin: 'http://localhost:3000' })
save = (name) -> (data) -> this[name] = data._id


query('No resource')
.get('/foobar')
.err(400, 'No such resource')
.run()


query('Creating companies')
.post('/companies')
.res('Created company', (data) -> data.should.have.keys ['_id', 'notes', 'name'] )
.run()


query('Cascading delete')
.post('/companies', {})
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
.post('/companies')
.res('Created company', save 'company')
.post('/companies/#{company}/calls')
.res('Created call', save 'call1')
.post('/companies/#{company}/calls')
.res('Created call', save 'call2')
.post('/companies')
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







# 
# query('Nulling foreign keys when pointed item is removed')
# .post('/companies')
# .res('Created company', save 'company')
# .post('/companies/#{company}/calls')
# .res('Created call', save 'call1')
# .post('/companies/#{company}/calls')
# .res('Created call', save 'call2')
# .post('/companies/#{company}/meetings')
# .res('Created meeting', save 'meeting')
# .put('/meetings/#{meeting}', () -> { origin: @call1 })
# .res('Set origin to call1')
# .get('/meetings/#{meeting}')
# .res('Getting meeting referring to call1', (data) -> data.origin.should.eql @call1)
# .del('/calls/#{call1}')
# .get('/meetings/#{meeting}')
# .res('Getting meeting referring to nothing', (data) -> should.not.exist data.origin)
# .run()
# 
# 
# 

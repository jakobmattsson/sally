nconf = require 'nconf'
should = require 'should'
mongojs = require 'mongojs'
trester = require '../trester/src/trester'
query = (text) -> trester.query(text, { origin: 'http://localhost:3000' })
save = (name) -> (data) -> this[name] = data.id


mongojs.connect('mongodb://localhost/sally').dropDatabase () ->
  require('./app').run({}, trester.trigger)


query('Root')
.get('/')
.res('Get root', (data) -> data.should.eql { roots: ['accounts', 'admins'], verbs: ['signup'] })
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



query('Can get accouts as admin')
.auth('admin', 'admin')
.get('/accounts')
.res('Got accounts')
.run()


query('User can only get own account')
.auth('admin', 'admin')
.post('/accounts', { name: 'a1' })
.res('Created account', save 'account')
.post('/accounts', { name: 'a2' })
.res('Created another account', save 'account2')
.post('/accounts/#{account}/users', { username: 'u1', password: 'pass' })
.res('Created user', save 'user')
.get('/accounts')
.res('Got all accounts as admin', (data) -> data.length.should.be.above 1)
.auth('u1', 'pass')
.get('/accounts')
.res('Get just one account as user', (data) -> data.length.should.eql 1)
.run()


query('There cant exist a user and an admin with the same name')
.auth('admin', 'admin')
.post('/admins', { username: 'collidingName', password: 'somepassword' })
.post('/accounts', { name: 'a3' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'collidingName', password: 'someotherpassword' })
.post('/accounts/#{account}/users', { username: 'collidingName', password: 'someotherpassword' })
.err(400, 'ValidationError: Validator failed for path username')
.run()



query('No one can access password for admins or users')
.auth('admin', 'admin')
.post('/admins', { username: 'admin1', password: 'admin1' })
.res('Created admin', save 'admin')
.post('/accounts', { name: 'a4' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'user1', password: 'user1' })
.post('/accounts/#{account}/users', { username: 'user2', password: 'user2', accountAdmin: true })
.get('/admins/#{admin}')
.res('Gets all admin info, except password', (data) -> data.should.have.keys('username', 'id'))
.get('/accounts/#{account}/users')
.res('Gets all user info, except password', (data) -> data.forEach (x) -> x.should.have.keys('username', 'id', 'accountAdmin', 'account'))
.auth('user1', 'user1')
.get('/accounts/#{account}/users')
.res('Gets all user info, except password, as user', (data) -> data.forEach (x) -> x.should.have.keys('username', 'id', 'accountAdmin', 'account'))
.run()



query('Users can only see themselves, unless they are account admins, in which case they can see the same account')
.auth('admin', 'admin')
.post('/accounts', { name: 'a5' })
.res('Created account', save 'account1')
.post('/accounts/#{account1}/users', { username: 'user1', password: 'user1' })
.post('/accounts/#{account1}/users', { username: 'user2', password: 'user2', accountAdmin: true })
.post('/accounts', { name: 'a6' })
.res('Created account', save 'account2')
.post('/accounts/#{account2}/users', { username: 'user3', password: 'user3', accountAdmin: true })
.auth('user1', 'user1')
.get('/users')
.res('Regular user sees only himself', (data) -> data.should.have.lengthOf(1); data[0].username.should.eql('user1'))
.auth('user2', 'user2')
.get('/users')
.res('Admin user sees all users in same account', (data) -> data.should.have.lengthOf(2); data[0].username.should.eql('user1'); data[1].username.should.eql('user2');)
.auth('user3', 'user3')
.get('/users')
.res('Lone admin user user sees only himself', (data) -> data.should.have.lengthOf(1); data[0].username.should.eql('user3'))
.run()






query('No resource')
.auth('admin', 'admin')
.get('/foobar')
.err(400, 'No such resource')
.run()


query('No id')
.auth('admin', 'admin')
.get('/companies/123456781234567812345678')
.err(400, 'No such id')
.run()


query('Testing so invalid IDs return the same error message as nonexisting IDs')
.auth('admin', 'admin')
.get('/companies/1234')
.err(400, 'No such id')
.run()



query('Creating companies')
.auth('admin', 'admin')
.post('/accounts', { name: 'a7' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', (data) -> data.should.have.keys ['id', 'notes', 'name', 'address', 'account'])
.run()



query('Attempting to save nonexisting field')
.auth('admin', 'admin')
.post('/accounts', { name: 'a8' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { nonExistingField: 'something', another: 2 })
.err(400, "Invalid fields: nonExistingField, another")
.run()



query('Ensure that PUT-operations are atomic')
.auth('admin', 'admin')
.post('/accounts', { name: 'a9' })
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
.auth('admin', 'admin')
.post('/accounts', { name: 'a10' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { id: '123456781234567812345678' })
.err(400)
.run()



query('Attempting to override _id')
.auth('admin', 'admin')
.post('/accounts', { name: 'a11' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { _id: '123456781234567812345678' })
.err(400)
.run()



query('Cascading delete')
.auth('admin', 'admin')
.post('/accounts', { name: 'a12' })
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
.auth('admin', 'admin')
.post('/accounts', { name: 'a13' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.post('/companies/#{company}/calls')
.res('Created call', save 'call1')
.post('/companies/#{company}/calls')
.res('Created call', save 'call2')
.post('/accounts', { name: 'a14' })
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
.auth('admin', 'admin')
.post('/accounts', { name: 'a15' })
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
.auth('admin', 'admin')
.post('/accounts', { name: 'a16' })
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
.auth('admin', 'admin')
.post('/accounts', { name: 'a17' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'foo', password: 'baz' })
.res('Created user', (data) -> data.should.include { username: 'foo', accountAdmin: false })
.run()



query('Attempting to create another user with the same username')
.auth('admin', 'admin')
.post('/accounts', { name: 'a18' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'foo', password: 'baz' })
.err(400, "Duplicate value 'foo' for username")
.run()



query('Attempting to create user without username or password')
.auth('admin', 'admin')
.post('/accounts', { name: 'a19' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users')
.err(400, 'ValidationError: Validator "required" failed for path password, Validator "required" failed for path username')
.run()



query('Setting a boolean type by passing in any truthy value')
.auth('admin', 'admin')
.post('/accounts', { name: 'a20' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'foobar', password: 'baz', accountAdmin: 'yes' })
.res('Created user', (data) -> data.should.include { username: 'foobar', accountAdmin: true })
.run()



query('Setting a boolean type by passing in any falsy value')
.auth('admin', 'admin')
.post('/accounts', { name: 'a21' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'foz', password: 'baz', accountAdmin: 0 })
.res('Created user', (data) -> data.should.include { username: 'foz', accountAdmin: false })
.run()



query('Testing security access between accounts')
.auth('admin', 'admin')
.post('/accounts', { name: 'a22' })
.res('Created account #1', save 'account1')
.post('/accounts/#{account1}/users', { username: 'test_u1', 'password': '123' })
.res('Created user #1', save 'user1')
.post('/accounts/#{account1}/companies')
.res('Created company #1', save 'company1')
.post('/accounts', { name: 'a23' })
.res('Created account #2', save 'account2')
.post('/accounts/#{account2}/users', { username: 'test_u2', 'password': '123', accountAdmin: true })
.res('Created user #2', save 'user2')
.auth('test_u2', '123')
.get('/accounts/#{account1}')
.err(400, 'No such id')
.del('/accounts/#{account1}')
.err(400, 'No such id')
.put('/accounts/#{account1}', { name: 'test' })
.err(400, 'No such id')
.get('/accounts/#{account1}/companies')
.err(400, 'No such id')
.get('/companies')
.res('Getting no companies', (data) -> data.should.have.lengthOf 0)
.run()



query('Testing read, write and create auths for accounts')
.auth('admin', 'admin')
.post('/accounts', { name: 'a24' })
.res('Created account #1', save 'account1')
.post('/accounts', { name: 'a25' })
.res('Created account #2', save 'account2')
.post('/accounts/#{account1}/users', { username: 'ua1', password: 'p', accountAdmin: true })
.res('Created user #1', save 'user1')
.post('/accounts/#{account1}/users', { username: 'ua2', password: 'p', accountAdmin: false })
.res('Created user #2', save 'user2')
.auth('admin', 'admin')
.get('/accounts')
.res('Reading accounts as admin', (data) -> data.length.should.be.above 1)
.put('/accounts/#{account1}', { name: 'new_name' })
.res('Updating account as admin', (data) -> data.should.include { name: 'new_name' })
.auth('ua1', 'p')
.get('/accounts')
.res('Reading accounts as account admin', (data) -> data.should.have.lengthOf 1)
.put('/accounts/#{account1}', { name: 'new_name_again' })
.res('Updating account as account admin', (data) -> data.should.include { name: 'new_name_again' })
.post('/accounts', { name: 'a26' })
.err(401, 'unauthed')
.auth('ua2', 'p')
.get('/accounts')
.res('Reading accounts as user', (data) -> data.should.have.lengthOf 1)
.put('/accounts/#{account1}', { name: 'new_name_again' })
.err(401, 'unauthed')
.post('/accounts', { name: 'a27' })
.err(401, 'unauthed')
.run()



query('Special signup route')
.auth('admin', 'admin')
.post('/accounts', { name: 'busyAccount' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'busyUser', password: 'some_password' })
.auth()
.post('/signup', { username: 'apa' })
.err(400, 'Could not create account')
.post('/signup', { username: 'busyUser', password: 'something', account: 'myAccountName' })
.err(400, 'Could not create user')
.post('/signup', { username: 'myUsername', password: 'something', account: 'busyAccount' })
.err(400, 'Could not create account')
.post('/signup', { username: 'myUsername', password: 'something', account: 'myAccountName' })
.res('Signed up apa', save('newAccount'))
.auth('myUsername', 'something')
.get('/accounts/#{newAccount}')
.res('Getting new account', (data) -> data.should.include { name: 'myAccountName' })
.get('/accounts/#{newAccount}/users')
.res('Getting new user', (data) -> data.should.have.lengthOf(1); data[0].should.include { username: 'myUsername', accountAdmin: true })
.run()


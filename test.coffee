_ = require 'underscore'
nconf = require 'nconf'
should = require 'should'
mongojs = require 'mongojs'
trester = require 'trester'
locke = require 'locke'

db = locke.db.mem.init()
emailClient = locke.emailMock.setup({ folder: 'tests/emails' })
api = locke.api.init(db, 1, emailClient)
locke.server.run(api, db, 6002)

createApp = (api, app, callback) ->
  email = 'owning-user-' + app
  password = 'allfornought'
  api.createUser 'locke', email, password, (err) ->
    return callback(err) if (err)
    api.authPassword 'locke', email, password, 86400, (err, res) ->
      return callback(err) if (err)
      api.createApp(email, res.token, app, callback)

query = (text) ->
  q = trester.query(text, { origin: 'http://localhost:3001' })
  auth = q.auth
  q.auth = (username, password) ->
    auth (callback) ->
      api.authPassword 'sally', username, password, 86400, (err, res) ->
        return callback(err) if err?
        callback(username, res?.token)
    this
  q

save = (name) -> (data) -> this[name] = data.id

defaultPassword = 'summertime'

mongojs.connect('mongodb://localhost/sally-test').dropDatabase () ->
  createApp api, 'sally', (err) ->
    require('./src/app').run { port: 3001, mongo: 'mongodb://localhost/sally-test' }, () ->
      trester.trigger()


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
.auth('admin0', defaultPassword)
.get('/accounts')
.res('Got accounts')
.run()


query('User can only get own account')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a1' })
.res('Created account', save 'account')
.post('/accounts', { name: 'a2' })
.res('Created another account', save 'account2')
.post('/accounts/#{account}/users', { username: 'u1', password: 'passpass' })
.res('Created user', save 'user')
.get('/accounts')
.res('Got all accounts as admin', (data) -> data.length.should.be.above 1)
.auth('u1', 'passpass')
.get('/accounts')
.res('Get just one account as user', (data) -> data.length.should.eql 1)
.run()


query('There cant exist a user and an admin with the same name')
.auth('admin0', defaultPassword)
.post('/admins', { username: 'collidingName', password: 'somepassword' })
.post('/accounts', { name: 'a3' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'collidingName', password: 'someotherpassword' })
.post('/accounts/#{account}/users', { username: 'collidingName', password: 'someotherpassword' })
.err(400, 'ValidationError: Validator failed for path username')
.run()



query('No one can access password for admins or users')
.auth('admin0', defaultPassword)
.post('/admins', { username: 'admin1', password: 'admin1' })
.res('Created admin', save 'admin')
.post('/accounts', { name: 'a4' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'user1', password: 'user1_' })
.post('/accounts/#{account}/users', { username: 'user2', password: 'user2_', accountAdmin: true })
.get('/admins/#{admin}')
.res('Gets all admin info, except password', (data) -> data.should.have.keys('username', 'id'))
.get('/accounts/#{account}/users')
.res('Gets all user info, except password', (data) -> data.forEach (x) -> x.should.have.keys('username', 'id', 'accountAdmin', 'account', 'nickname'))
.auth('user1', 'user1_')
.get('/accounts/#{account}/users')
.res('Gets all user info, except password, as user', (data) -> data.forEach (x) -> x.should.have.keys('username', 'id', 'accountAdmin', 'account', 'nickname'))
.run()



query('Users can only see themselves, unless they are account admins, in which case they can see the same account')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a5' })
.res('Created account', save 'account1')
.post('/accounts/#{account1}/users', { username: 'abc-user1', password: 'user1_' })
.res('Created user1', save 'user1')
.post('/accounts/#{account1}/users', { username: 'abc-user2', password: 'user2_', accountAdmin: true })
.res('Created user2', save 'user2')
.post('/accounts', { name: 'a6' })
.res('Created account', save 'account2')
.post('/accounts/#{account2}/users', { username: 'abc-user3', password: 'user3_', accountAdmin: true })
.auth('abc-user1', 'user1_')
.get('/users')
.res('Regular user sees all users in the same account', (data) -> data.should.have.lengthOf(2))
.put('/users/#{user2}', { username: 'woot' })
.err(400, 'No such id') # should say something like "no write access" instead
.auth('abc-user2', 'user2_')
.get('/users')
.res('Admin user sees all users in same account', (data) -> data.should.have.lengthOf(2); data[0].username.should.eql('abc-user1'); data[1].username.should.eql('abc-user2');)
.auth('abc-user3', 'user3_')
.get('/users')
.res('Lone admin user user sees only himself', (data) -> data.should.have.lengthOf(1); data[0].username.should.eql('abc-user3'))
.run()






query('No resource')
.auth('admin0', defaultPassword)
.get('/foobar')
.err(400, 'No such resource')
.run()


query('No id')
.auth('admin0', defaultPassword)
.get('/companies/123456781234567812345678')
.err(400, 'No such id')
.run()


query('Testing so invalid IDs return the same error message as nonexisting IDs')
.auth('admin0', defaultPassword)
.get('/companies/1234')
.err(400, 'No such id')
.run()



query('Creating companies')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a7' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', (data) -> data.should.have.keys ['id', 'notes', 'name', 'address', 'account', 'orgnr', 'city', 'zip', 'about', 'website'])
.run()



query('Attempting to save nonexisting field')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a8' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { nonExistingField: 'something', another: 2 })
.err(400, "Invalid fields: nonExistingField, another")
.run()



query('Ensure that PUT-operations are atomic')
.auth('admin0', defaultPassword)
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
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a10' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { id: '123456781234567812345678' })
.err(400)
.run()



query('Attempting to override _id')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a11' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.put('/companies/#{company}', { _id: '123456781234567812345678' })
.err(400)
.run()



query('Cascading delete')
.auth('admin0', defaultPassword)
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
.auth('admin0', defaultPassword)
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
.auth('admin0', defaultPassword)
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
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a16' })
.res('Created account', save 'account')
.post('/accounts/#{account}/companies')
.res('Created company', save 'company')
.post('/companies/#{company}/contacts').res('Created first contact', save 'contact1')
.post('/companies/#{company}/contacts').res('Created second contact', save 'contact2')
.post('/companies/#{company}/meetings').res('Created meeting', save 'meeting')
.post('/meetings/#{meeting}/attendingContacts/#{contact1}')
.res('Settings first contact to meeting', (data) -> data.should.eql {})
.post('/attendingContacts/#{contact2}/meetings/#{meeting}')
.res('Settings second contact to meeting', (data) -> data.should.eql {})
.get('/meetings/#{meeting}/attendingContacts')
.res('Getting all meeting attendees', (data) ->
  data.should.have.lengthOf 2
  data[0].should.include { company: @company, id: @contact1 }
  data[1].should.include { company: @company, id: @contact2 }
)
.get('/attendingContacts/#{contact1}/meetings')
.res('Getting the meetings from an attendant', (data) ->
  data.should.have.lengthOf(1)
  data[0].should.have.property 'account'
  data[0].attendingContacts.should.eql [@contact1, @contact2]
  data[0].should.have.property 'company', @company
  data[0].should.have.property 'notes', ''
  data[0].should.have.property 'when', null
  data[0].should.have.property 'id', @meeting
)
.del('/meetings/#{meeting}/attendingContacts/#{contact1}')
.res('Removed contact from meeting', (data) -> data.id.should.eql @contact1)
.del('/attendingContacts/#{contact2}/meetings/#{meeting}')
.res('Removed meeting from contact', (data) -> data.id.should.eql @meeting)
.get('/companies/#{company}/contacts')
.res('All contacts should still be in the db', (data) -> data.length.should.eql 2)
.get('/companies/#{company}/meetings')
.res('All meetings should still be in the db', (data) -> data.length.should.eql 1)
.get('/meetings/#{meeting}/attendingContacts')
.res('Getting all meeting attendingContacts', (data) -> data.should.eql [])
.run()



query('Test meta owns')
.get('/meta/accounts').res('Meta for accounts', (data) -> data.owns.should.eql ['users', 'companies'])
.get('/meta/companies').res('Meta for companies', (data) -> data.owns.should.eql ['projects', 'emails', 'calls', 'meetings', 'contacts'])
.get('/meta/calls').res('Meta for calls', (data) -> data.owns.should.eql [])
.get('/meta/meetings').res('Meta for meetings', (data) -> data.owns.should.eql [])
.get('/meta/projects').res('Meta for projects', (data) -> data.owns.should.eql [])
.get('/meta/contacts').res('Meta for contacts', (data) -> data.owns.should.eql [])
.run()


query('Test meta fields')
.get('/meta/accounts').res('Meta fields for accounts', (data) -> data.fields.should.eql [{ name: 'id', type: 'string', readonly: true, required: false }, { name: 'name', type: 'string', readonly: false, required: true }])
.get('/meta/projects').res('Meta fields for projects', (data) -> data.fields.should.eql [{ name: 'account', type: 'string', readonly: true, required: true }, { name: 'company', type: 'string', readonly: true, required: true }, { name: 'description', type: 'string', readonly: false, required: false }, { name: 'id', type: 'string', readonly: true, required: false }, { name: 'value', type: 'number', readonly: false, required: false }])
.get('/meta/companies').res('Meta fields for companies', (data) -> data.fields.should.eql([
  { name: 'about', type: 'string', readonly: false, required: false }
  { name: 'account', type: 'string', readonly: true, required: true }
  { name: 'address', type: 'string', readonly: false, required: false }
  { name: 'city', type: 'string', readonly: false, required: false }
  { name: 'id', type: 'string', readonly: true, required: false }
  { name: 'name', type: 'string', readonly: false, required: false }
  { name: 'nextCall', type: 'date', readonly: false, required: false }
  { name: 'nextCallStrict', type: 'boolean', readonly: false, required: false }
  { name: 'notes', type: 'string', readonly: false, required: false }
  { name: 'orgnr', type: 'string', readonly: false, required: false }
  { name: 'seller', type: 'string', readonly: false, required: false }
  { name: 'website', type: 'string', readonly: false, required: false }
  { name: 'zip', type: 'string', readonly: false, required: false }
]))
.run()



query('Creating users')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a17' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'foo', password: 'bazbaz' })
.res('Created user', (data) -> data.should.include { username: 'foo', accountAdmin: false })
.run()



query('Attempting to create another user with the same username')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a18' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'foo', password: 'bazbaz' })
.err(400, "Duplicate value 'foo' for username")
.run()



query('Attempting to create user without username or password')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a19' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users')
.err(400, 'ValidationError: Validator "required" failed for path username')
.run()



query('Setting a boolean type by passing in any truthy value')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a20' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'foobar', password: 'bazbaz', accountAdmin: 'yes' })
.res('Created user', (data) -> data.should.include { username: 'foobar', accountAdmin: true })
.run()



query('Setting a boolean type by passing in any falsy value')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a21' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'foz', password: 'bazbaz', accountAdmin: 0 })
.res('Created user', (data) -> data.should.include { username: 'foz', accountAdmin: false })
.run()



query('Testing security access between accounts')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a22' })
.res('Created account #1', save 'account1')
.post('/accounts/#{account1}/users', { username: 'test_u1', 'password': '123baz' })
.res('Created user #1', save 'user1')
.post('/accounts/#{account1}/companies')
.res('Created company #1', save 'company1')
.post('/accounts', { name: 'a23' })
.res('Created account #2', save 'account2')
.post('/accounts/#{account2}/users', { username: 'test_u2', 'password': '123baz', accountAdmin: true })
.res('Created user #2', save 'user2')
.auth('test_u2', '123baz')
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
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a24' })
.res('Created account #1', save 'account1')
.post('/accounts', { name: 'a25' })
.res('Created account #2', save 'account2')
.post('/accounts/#{account1}/users', { username: 'ua1', password: 'p12345', accountAdmin: true })
.res('Created user #1', save 'user1')
.post('/accounts/#{account1}/users', { username: 'ua2', password: 'p12345', accountAdmin: false })
.res('Created user #2', save 'user2')
.auth('admin0', defaultPassword)
.get('/accounts')
.res('Reading accounts as admin', (data) -> data.length.should.be.above 1)
.put('/accounts/#{account1}', { name: 'new_name' })
.res('Updating account as admin', (data) -> data.should.include { name: 'new_name' })
.auth('ua1', 'p12345')
.get('/accounts')
.res('Reading accounts as account admin', (data) -> data.should.have.lengthOf 1)
.put('/accounts/#{account1}', { name: 'new_name_again' })
.res('Updating account as account admin', (data) -> data.should.include { name: 'new_name_again' })
.post('/accounts', { name: 'a26' })
.err(401, 'unauthed')
.auth('ua2', 'p12345')
.get('/accounts')
.res('Reading accounts as user', (data) -> data.should.have.lengthOf 1)
.put('/accounts/#{account1}', { name: 'new_name_again' })
.err(401, 'unauthed')
.post('/accounts', { name: 'a27' })
.err(401, 'unauthed')
.run()



query('Special signup route (unique user)')
.post('/signup', { username: 'u12345', password: 'p12345' })
.res('Created account', (data) -> data.should.have.keys ['id', 'name'])
.auth('u12345', 'p12345')
.get('/users')
.res('Getting new user', (data) -> data.should.have.lengthOf(1); data[0].should.include { username: 'u12345', accountAdmin: true, nickname: '' })
.run()



query('Special signup route (user that already exists)')
.post('/signup', { username: 'u12345', password: 'p12345' })
.err(400, 'Could not create user')
.run()



query('Special signup route (invited user)')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'acc1' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'us1234' })
.auth()
.post('/signup', { username: 'us1234', password: 'p12345' })
.auth('us1234', 'p12345')
.get('/users')
.res('Getting new user', (data) -> data.should.have.lengthOf(1); data[0].should.include { username: 'us1234', accountAdmin: false, nickname: '' })
.run()



query('Special signup route')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'busyAccount' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'busyUser', password: 'some_password' })
.auth()
.post('/signup', { username: 'apa' })
.err(400, 'Could not create user') # no password
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



# query('Special signup route')
# .auth('admin0', defaultPassword)
# .post('/accounts', { name: 'natural' })
# .res('Making sure the name is used as the natural id', (data) -> data.should.eql { id: 'natural', name: 'natural' })
# .run()



query('Setting the seller for a company')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a30' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'foo30', password: 'bazbaz', accountAdmin: true })
.res('Created user', save 'u1')
.post('/accounts/#{account}/users', { username: 'foo31', password: 'bazbaz', accountAdmin: false })
.res('Created user', save 'u2')
.post('/accounts/#{account}/companies', { name: 'cool ab' })
.res('Created company', save 'company')
.res('Getting new account', (data) -> data.should.include { seller: undefined })
.put('/companies/#{company}', -> { seller: this.u1 })
.get('/companies/#{company}')
.res('Getting new company', (data) -> data.should.include { seller: this.u1 })
.run()



query('An admin should not be able to create a user without specing an account')
.auth('admin0', defaultPassword)
.post('/users', { name: 'u2-1' })
.err(400, 'Missing owner')
.run()



query('An account admin should be able to create a user without specing an account')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a101' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'a101-u1', password: 'p1p1p1', accountAdmin: true })
.res('Created user', save 'user')
.auth('a101-u1', 'p1p1p1')
.post('/users', { username: 'a101-u2' })
.res('Created user', (data) -> data.should.include { username: 'a101-u2', accountAdmin: false })
.run()



query('A regular user should not be able to create a user without specing an account')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a102' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'a102-u1', password: 'p1p1p1', accountAdmin: false })
.res('Created user', save 'user')
.auth('a102-u1', 'p1p1p1')
.post('/users', { name: 'a102-u2' })
.err(401)
.run()



query('A regular user should be able to create a company without specing an account')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a103' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'a103-u1', password: 'p1p1p1', accountAdmin: false })
.res('Created user', save 'user')
.auth('a103-u1', 'p1p1p1')
.post('/companies', { name: 'a103-name' })
.res('Created company', (data) -> data.should.include { name: 'a103-name', orgnr: '' })
.run()



query('A regular user should be able to create a meeting without specing a company')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a104' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'a104-u1', password: 'p1p1p1', accountAdmin: false })
.res('Created user', save 'user')
.auth('a104-u1', 'p1p1p1')
.post('/meetings', { notes: 'testing' })
.err(400, 'Missing owner')
.run()


query('Sorting accounts')
.auth('admin0', defaultPassword)
.post('/accounts', { name: 'a110' })
.res('Created account', save 'account')
.post('/accounts/#{account}/users', { username: 'a110-u1' })
.post('/accounts/#{account}/users', { username: 'a110-u3' })
.post('/accounts/#{account}/users', { username: 'a110-u2' })
.get('/accounts/#{account}/users')
.res('Got all accounts as admin', (data) -> _(data).pluck('username').should.eql ['a110-u1', 'a110-u2', 'a110-u3'])
.run()


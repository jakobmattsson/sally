http = require 'http'
async = require 'async'
_ = require 'underscore'
mongoose = require 'mongoose'
express = require 'express'
ObjectId = mongoose.Schema.ObjectId

app = express.createServer()
app.use express.bodyParser()

mongoose.connect 'mongodb://localhost/sally'

model = (name, schema) ->
  ss = new mongoose.Schema schema,
    strict: true
  mongoose.model name, ss

list = (model, callback) ->
  model.find {}, callback

get = (model, id, callback) ->
  model.findById id, (err, data) ->
    if err
      callback err
    else if !data
      callback "No such id"
    else
      callback(err, data)
      
  

del = (model, id, callback) ->
  model.findById id, (err, d) ->
    if err
      callback err
      return
    if !d
      callback "No object with that id"
      return
    d.remove (err) ->
      callback err, if !err then d

put = (model, id, data, callback) ->
  model.findById id, (err, d) ->
    if err
      callback err
      return
  
    Object.keys(data).forEach (key) ->
      d[key] = data[key]

    d.save (err) ->
      callback(err, if err then null else d)
  
  

post = (model, data, callback) ->
  new model(data).save callback

postSub = (model, data, outer, id, callback) ->
  data[outer] = id
  new model(data).save callback

listSub = (model, outer, id, callback) ->
  filter = {}
  filter[outer] = id
  model.find filter, callback


models = {}



exports.defModel = (name, owners, spec) ->

  Object.keys(owners).forEach (ownerName) ->
    spec[ownerName] =
      type: ObjectId
      ref: owners[ownerName]
      'x-owner': true

  Object.keys(spec).forEach (fieldName) ->
    if spec[fieldName].ref?
      spec[fieldName].type = ObjectId

  models[name] = model name, spec



# checking that nullable relations are set to values that exist
nullablesValidation = (schema) -> (next) ->

  self = this
  paths = schema.paths
  outers = Object.keys(paths).filter((x) -> paths[x].options.type == ObjectId && typeof paths[x].options.ref == 'string' && !paths[x].options['x-owner']).map (x) ->
    plur: paths[x].options.ref
    sing: x
    validation: paths[x].options['x-validation']

  # setting to null is always ok
  nonNullOuters = outers.filter (x) -> self[x.sing]?

  async.forEach nonNullOuters, (o, callback) ->
    get models[o.plur], self[o.sing], (err, data) ->
      if err || !data
        callback(new Error("Invalid pointer"))
      else if o.validation
        o.validation self, data, callback
      else
        callback()
  , next


preRemoveCascadeDown = (owner, id, next) ->

  ownedModels = Object.keys(models).map (modelName) ->
    paths = models[modelName].schema.paths
    Object.keys(paths).filter((x) -> paths[x].options.type == ObjectId && paths[x].options.ref == owner.modelName && paths[x].options['x-owner']).map (x) ->
      name: modelName
      field: x

  flattenedModels = _.flatten ownedModels

  async.forEach flattenedModels, (mod, callback) ->
    listSub models[mod.name], mod.field, id, (err, data) ->
      async.forEach data, (item, callback) ->
        item.remove callback
      , callback
  , next




exports.exec = () ->

  Object.keys(models).map((x) -> models[x]).forEach (model) ->
    model.schema.pre 'save', nullablesValidation(model.schema)


  Object.keys(models).map((x) -> models[x]).forEach (model) ->
    model.schema.pre 'remove', (next) -> preRemoveCascadeDown(model, this._id.toString(), next)



  def = (method, route, callback) ->
    app[method](route, callback)

  responder = (res) ->
    (err, data) ->
      if err
        res.json { err: err.toString() }, 400
      else
        res.json data

  Object.keys(models).forEach (modelName) ->

    def 'get', "/#{modelName}", (req, res) ->
      list models[modelName], responder(res)

    def 'get', "/#{modelName}/:id", (req, res) ->
      get models[modelName], req.params.id, responder(res)

    def 'del', "/#{modelName}/:id", (req, res) ->
      del models[modelName], req.params.id, responder(res)

    def 'put', "/#{modelName}/:id", (req, res) ->
      put models[modelName], req.params.id, req.body, responder(res)

    paths = models[modelName].schema.paths
    outers = Object.keys(paths).filter((x) -> paths[x].options['x-owner']).map (x) ->
      plur: paths[x].options.ref
      sing: x

    if outers.length == 0
      def 'post', "/#{modelName}", (req, res) ->
        post models[modelName], req.body, responder(res)

    outers.forEach (outer) ->
      def 'get', "/#{outer.plur}/:id/#{modelName}", (req, res) ->
        listSub models[modelName], outer.sing, req.params.id, responder(res)

      def 'post', "/#{outer.plur}/:id/#{modelName}", (req, res) ->
        postSub models[modelName], req.body, outer.sing, req.params.id, responder(res)


  app.get '/', (req, res) ->
    res.json
      roots: ['companies'] # generera istället
      verbs: []

  app.all '*', (req, res) ->
    res.json { err: 'No such resource' }, 400

  app.listen 3000

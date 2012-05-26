http = require 'http'
async = require 'async'
_ = require 'underscore'
underscore = require 'underscore'
mongoose = require 'mongoose'
mongojs = require 'mongojs'
express = require 'express'
ObjectId = mongoose.Schema.ObjectId

app = express.createServer()
app.use express.bodyParser()

mongoose.connect 'mongodb://localhost/sally'
db = mongojs.connect 'mongodb://localhost/sally', ['meetings', 'companies', 'contacts', 'projects', 'calls'] # fult att hårdkoda collections


propagate = (callback, f) ->
  (err, args...) ->
    if err
      callback(err)
    else
      f.apply(this, args)


model = (name, schema) ->
  ss = new mongoose.Schema schema,
    strict: true
  mongoose.model name, ss

list = (model, callback) ->
  model.find {}, callback

get = (model, id, callback) ->
  model.findById id, propagate callback, (data) ->
    callback((if !data? then "No such id"), data)

del = (model, id, callback) ->
  model.findById id, propagate callback, (d) ->
    if !d?
      callback "No such id"
    else
      d.remove (err) ->
        callback err, if !err then d

put = (model, id, data, callback) ->

  inputFields = Object.keys data
  validField = Object.keys(model.schema.paths)

  invalidFields = _.difference(inputFields, validField)

  if invalidFields.length > 0
    callback("Invalid fields: " + invalidFields.join(', '))
    return

  model.findById id, propagate callback, (d) ->
    inputFields.forEach (key) ->
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

delMany = (primaryModel, primaryId, propertyName, secondaryModel, secondaryId, callback) ->
  models[primaryModel].findById primaryId, propagate callback, (data) ->

    pull = {}
    pull[propertyName] = secondaryId
    conditions = { _id: primaryId }
    update = { $pull: pull }
    options = { }

    models[primaryModel].update conditions, update, options, (err, numAffected) ->
      callback(err)

postMany = (primaryModel, primaryId, propertyName, secondaryModel, secondaryId, callback) ->
  models[primaryModel].findById primaryId, propagate callback, (data) ->
    models[secondaryModel].findById secondaryId, propagate callback, () ->

      if -1 == data[propertyName].indexOf secondaryId
        data[propertyName].push secondaryId

      data.save (err) ->
        callback(err, {})

getMany = (primaryModel, primaryId, propertyName, callback) ->

  models[primaryModel]
  .findOne({ _id: primaryId })
  .populate(propertyName)
  .run (err, story) ->
    callback err, story[propertyName]

getManyBackwards = (model, id, propertyName, callback) ->
  filter = {}
  filter[propertyName] = new db.bson.ObjectID(id.toString())

  db[model].find filter, (err, result) ->
    callback(err, result)



models = {}

exports.ObjectId = ObjectId;

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
        o.validation self, data, (err) ->
          callback(if err then new Error(err))
      else
        callback()
  , next


preRemoveCascadeNonNullable = (owner, id, next) ->

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



preRemoveCascadeNullable = (owner, id, next) ->

  ownedModels = Object.keys(models).map (modelName) ->
    paths = models[modelName].schema.paths
    Object.keys(paths).filter((x) -> paths[x].options.type == ObjectId && paths[x].options.ref == owner.modelName && !paths[x].options['x-owner']).map (x) ->
      name: modelName
      field: x

  flattenedModels = _.flatten ownedModels

  async.forEach flattenedModels, (mod, callback) ->
    listSub models[mod.name], mod.field, id, (err, data) ->
      async.forEach data, (item, callback) ->
        item[mod.field] = null
        item.save()
        callback()
      , callback
  , next




exports.exec = () ->

  Object.keys(models).map((x) -> models[x]).forEach (model) ->
    model.schema.pre 'save', nullablesValidation(model.schema)


  Object.keys(models).map((x) -> models[x]).forEach (model) ->
    model.schema.pre 'remove', (next) -> preRemoveCascadeNonNullable(model, this._id.toString(), next)

  Object.keys(models).map((x) -> models[x]).forEach (model) ->
    model.schema.pre 'remove', (next) -> preRemoveCascadeNullable(model, this._id.toString(), next)


  def = (method, route, mid, callback) ->
    if !callback?
      callback = mid
      mid = []

    # console.log method, route
    app[method](route, mid, callback)

  responder = (res) ->
    (err, data) ->
      if err
        res.json { err: err.toString() }, 400
      else
        res.json(massageResult(JSON.parse(JSON.stringify(data))))

  validateId = (req, res, next) ->
    try
      mongoose.mongo.ObjectID(req.params.id)
    catch ex
      res.json { err: 'No such id' }, 400 # duplication. can this be extracted out?
      return
    next()

  massageOne = (x) ->
    x.id = x._id
    delete x._id
    x

  massageResult = (r2) -> if Array.isArray r2 then r2.map massageOne else massageOne r2


  Object.keys(models).forEach (modelName) ->

    def 'get', "/#{modelName}", (req, res) ->
      list models[modelName], responder(res)

    def 'get', "/#{modelName}/:id", validateId, (req, res) ->
      get models[modelName], req.params.id, responder(res)

    def 'del', "/#{modelName}/:id", validateId, (req, res) ->
      del models[modelName], req.params.id, responder(res)

    def 'put', "/#{modelName}/:id", validateId, (req, res) ->
      put models[modelName], req.params.id, req.body, responder(res)

    paths = models[modelName].schema.paths
    outers = Object.keys(paths).filter((x) -> paths[x].options['x-owner']).map (x) ->
      plur: paths[x].options.ref
      sing: x

    manyToMany = Object.keys(paths).filter((x) -> Array.isArray paths[x].options.type).map (x) ->
      ref: paths[x].options.type[0].ref
      name: x

    if outers.length == 0
      def 'post', "/#{modelName}", (req, res) ->
        post models[modelName], req.body, responder(res)

    outers.forEach (outer) ->
      def 'get', "/#{outer.plur}/:id/#{modelName}", validateId, (req, res) ->
        listSub models[modelName], outer.sing, req.params.id, responder(res)

      def 'post', "/#{outer.plur}/:id/#{modelName}", validateId, (req, res) ->
        postSub models[modelName], req.body, outer.sing, req.params.id, responder(res)

    manyToMany.forEach (many) ->
      def 'post', "/#{modelName}/:id/#{many.name}/:other", (req, res) ->
        postMany modelName, req.params.id, many.name, many.ref, req.params.other, responder(res)

      def 'post', "/#{many.name}/:other/#{modelName}/:id", (req, res) ->
        postMany modelName, req.params.id, many.name, many.ref, req.params.other, responder(res)

      def 'get', "/#{modelName}/:id/#{many.name}", (req, res) ->
        getMany modelName, req.params.id, many.name, responder(res)

      def 'get', "/#{many.name}/:id/#{modelName}", (req, res) ->
        getManyBackwards modelName, req.params.id, many.name, responder(res)

      def 'del', "/#{modelName}/:id/#{many.name}/:other", (req, res) ->
        get models[many.ref], req.params.other, (err, data) ->
          delMany modelName, req.params.id, many.name, many.ref, req.params.other, (innerErr) ->
            responder(res)(err || innerErr, data)

      def 'del', "/#{many.name}/:other/#{modelName}/:id", (req, res) ->
        get models[modelName], req.params.id, (err, data) ->
          delMany modelName, req.params.id, many.name, many.ref, req.params.other, (innerErr) ->
            responder(res)(err || innerErr, data)


  app.get '/', (req, res) ->
    res.json
      roots: ['companies'] # generera istället
      verbs: []

  app.all '*', (req, res) ->
    res.json { err: 'No such resource' }, 400

  app.listen 3000

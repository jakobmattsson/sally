async = require 'async'
_ = require 'underscore'
mongoose = require 'mongoose'
mongojs = require 'mongojs'
ObjectId = mongoose.Schema.ObjectId

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






# The five base methods
# =====================
exports.list = (model, callback) ->
  model.find {}, callback

exports.get = (model, id, callback) ->
  model.findById id, propagate callback, (data) ->
    callback((if !data? then "No such id"), data)

exports.del = (model, id, callback) ->
  model.findById id, propagate callback, (d) ->
    if !d?
      callback "No such id"
    else
      d.remove (err) ->
        callback err, if !err then d

exports.put = (model, id, data, callback) ->
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

exports.post = (model, data, callback) ->
  new model(data).save callback



# Sub-methods
# ===========
exports.postSub = (model, data, outer, id, callback) ->
  data[outer] = id
  new model(data).save callback

exports.listSub = (model, outer, id, callback) ->
  filter = {}
  filter[outer] = id
  model.find filter, callback





# The many-to-many methods
# ========================
exports.delMany = (primaryModel, primaryId, propertyName, secondaryModel, secondaryId, callback) ->
  models[primaryModel].findById primaryId, propagate callback, (data) ->
    pull = {}
    pull[propertyName] = secondaryId
    conditions = { _id: primaryId }
    update = { $pull: pull }
    options = { }
    models[primaryModel].update conditions, update, options, (err, numAffected) ->
      callback(err)

exports.postMany = (primaryModel, primaryId, propertyName, secondaryModel, secondaryId, callback) ->
  models[primaryModel].findById primaryId, propagate callback, (data) ->
    models[secondaryModel].findById secondaryId, propagate callback, () ->

      if -1 == data[propertyName].indexOf secondaryId
        data[propertyName].push secondaryId

      data.save (err) ->
        callback(err, {})

exports.getMany = (primaryModel, primaryId, propertyName, callback) ->
  models[primaryModel]
  .findOne({ _id: primaryId })
  .populate(propertyName)
  .run (err, story) ->
    callback err, story[propertyName]

exports.getManyBackwards = (model, id, propertyName, callback) ->
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





exports.models = models










exports.exec = () ->




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
      exports.get models[o.plur], self[o.sing], (err, data) ->
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
      exports.listSub models[mod.name], mod.field, id, (err, data) ->
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
      exports.listSub models[mod.name], mod.field, id, (err, data) ->
        async.forEach data, (item, callback) ->
          item[mod.field] = null
          item.save()
          callback()
        , callback
    , next



  Object.keys(models).map((x) -> models[x]).forEach (model) ->
    model.schema.pre 'save', nullablesValidation(model.schema)

  Object.keys(models).map((x) -> models[x]).forEach (model) ->
    model.schema.pre 'remove', (next) -> preRemoveCascadeNonNullable(model, this._id.toString(), next)

  Object.keys(models).map((x) -> models[x]).forEach (model) ->
    model.schema.pre 'remove', (next) -> preRemoveCascadeNullable(model, this._id.toString(), next)

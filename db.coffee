async = require 'async'
_ = require 'underscore'
mongoose = require 'mongoose'
mongojs = require 'mongojs'
ObjectId = mongoose.Schema.ObjectId


exports.create = (databaseUrl) ->

  db = null
  api = {}
  models = {}
  api.ObjectId = ObjectId

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

  api.isValidId = (id) ->
    try
      mongoose.mongo.ObjectID(id)
      true
    catch ex
      false


  api.getFilter = (conf, model, callback) ->
    api.getUserFromDb db, conf, (err, user) ->
      if err
        callback err
        return
      filter = models[model]._auth(user)
      callback null, filter


  # Connecting to db
  # ================
  api.connect = (databaseUrl) ->
    mongoose.connect databaseUrl
    db = mongojs.connect databaseUrl, api.getModels()


  # The five base methods
  # =====================
  api.list = (model, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    models[model].find filter, callback

  api.get = (model, id, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    models[model].findById id, propagate callback, (data) ->
      callback((if !data? then "No such id"), data)

  api.del = (model, id, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    models[model].findById id, propagate callback, (d) ->
      if !d?
        callback "No such id"
      else
        d.remove (err) ->
          callback err, if !err then d

  api.put = (modelName, id, data, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    model = models[modelName]
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

  api.post = (model, data, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    new models[model](data).save callback



  # Sub-methods
  # ===========
  api.postSub = (model, data, outer, id, callback) ->
    data[outer] = id
    new models[model](data).save callback

  api.listSub = (model, outer, id, callback) ->
    filter = {}
    filter[outer] = id
    models[model].find filter, callback





  # The many-to-many methods
  # ========================
  api.delMany = (primaryModel, primaryId, propertyName, secondaryModel, secondaryId, callback) ->
    models[primaryModel].findById primaryId, propagate callback, (data) ->
      pull = {}
      pull[propertyName] = secondaryId
      conditions = { _id: primaryId }
      update = { $pull: pull }
      options = { }
      models[primaryModel].update conditions, update, options, (err, numAffected) ->
        callback(err)

  api.postMany = (primaryModel, primaryId, propertyName, secondaryModel, secondaryId, callback) ->
    models[primaryModel].findById primaryId, propagate callback, (data) ->
      models[secondaryModel].findById secondaryId, propagate callback, () ->

        if -1 == data[propertyName].indexOf secondaryId
          data[propertyName].push secondaryId

        data.save (err) ->
          callback(err, {})

  api.getMany = (primaryModel, primaryId, propertyName, callback) ->
    models[primaryModel]
    .findOne({ _id: primaryId })
    .populate(propertyName)
    .run (err, story) ->
      callback err, story[propertyName]

  api.getManyBackwards = (model, id, propertyName, callback) ->
    filter = {}
    filter[propertyName] = new db.bson.ObjectID(id.toString())

    db[model].find filter, (err, result) ->
      callback(err, result)






  specTransform = (tgt, src, keys) ->
    keys.forEach (key) ->
      if !src[key].type?
        throw "must assign a type: " + JSON.stringify(keys)
      if src[key].type == 'nested'
        tgt[key] = {}
        specTransform(tgt[key], src[key], _.without(Object.keys(src[key]), 'type'))
      if src[key].type == 'string'
        tgt[key] = { type: String, default: src[key].default }
      if src[key].type == 'number'
        tgt[key] = { type: Number, default: src[key].default }
      if src[key].type == 'hasOne'
        tgt[key] = { ref: src[key].model, 'x-validation': src[key].validation }
      if src[key].type == 'hasMany'
        tgt[key] = [{ type: ObjectId, ref: src[key].model }]

  api.defModel = (name, conf) ->

    spec = {}
    owners = conf.owners || {}
    inspec = conf.fields || {}
    auth = conf.auth || (() -> {})
    specTransform(spec, inspec, Object.keys(inspec))

    # set owners
    Object.keys(owners).forEach (ownerName) ->
      spec[ownerName] =
        type: ObjectId
        ref: owners[ownerName]
        'x-owner': true

    # set indirect owners (SHOULD use the full list of models, rather than depend on that indirect owners have been created already)
    Object.keys(owners).forEach (ownerName) ->
      paths = models[owners[ownerName]].schema.paths
      Object.keys(paths).filter((p) -> paths[p].options['x-owner']).forEach (p) ->
        spec[p] =
          type: ObjectId
          ref: paths[p].options.ref
          'x-indirect-owner': true

    Object.keys(spec).forEach (fieldName) ->
      if spec[fieldName].ref?
        spec[fieldName].type = ObjectId

    models[name] = model name, spec
    models[name]._auth = auth

    models[name].schema.pre 'save', nullablesValidation(models[name].schema)
    models[name].schema.pre 'remove', (next) -> preRemoveCascadeNonNullable(models[name], this._id.toString(), next)
    models[name].schema.pre 'remove', (next) -> preRemoveCascadeNullable(models[name], this._id.toString(), next)




  api.getMetaFields = (modelName) ->
    typeMap =
      ObjectID: 'string'
      String: 'string'
      Number: 'number'
    paths = models[modelName].schema.paths
    metaFields = Object.keys(paths).map (key) ->
      name: (if key == '_id' then 'id' else key)
      readonly: key == '_id' || !!paths[key].options['x-owner'] || !!paths[key].options['x-indirect-owner']
      type: typeMap[paths[key].instance] || 'unknown'
    _.sortBy(metaFields, 'name')

  api.getOwners = (modelName) ->
    paths = models[modelName].schema.paths
    outers = Object.keys(paths).filter((x) -> paths[x].options['x-owner']).map (x) ->
      plur: paths[x].options.ref
      sing: x
    outers

  api.getOwnedModels = (ownerModelName) ->
    _.flatten Object.keys(models).map (modelName) ->
      paths = models[modelName].schema.paths
      Object.keys(paths).filter((x) -> paths[x].options.type == ObjectId && paths[x].options.ref == ownerModelName && paths[x].options['x-owner']).map (x) ->
        name: modelName
        field: x

  api.getManyToMany = (modelName) ->
    paths = models[modelName].schema.paths
    manyToMany = Object.keys(paths).filter((x) -> Array.isArray paths[x].options.type).map (x) ->
      ref: paths[x].options.type[0].ref
      name: x
    manyToMany


  api.getModels = () ->
    Object.keys(models)



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
      api.get o.plur, self[o.sing], (err, data) ->
        if err || !data
          callback(new Error("Invalid pointer"))
        else if o.validation
          o.validation self, data, (err) ->
            callback(if err then new Error(err))
        else
          callback()
    , next

  preRemoveCascadeNonNullable = (owner, id, next) ->

    flattenedModels = api.getOwnedModels(owner.modelName)

    async.forEach flattenedModels, (mod, callback) ->
      api.listSub mod.name, mod.field, id, (err, data) ->
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
      api.listSub mod.name, mod.field, id, (err, data) ->
        async.forEach data, (item, callback) ->
          item[mod.field] = null
          item.save()
          callback()
        , callback
    , next

  api
